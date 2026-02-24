# frozen_string_literal: true

require 'timeout'

module RubyLLM
  module Providers
    class OpenAIResponses
      # WebSocket transport for the OpenAI Responses API.
      # Provides lower-latency agentic workflows by maintaining a persistent
      # wss:// connection instead of HTTP requests per turn.
      #
      # Requires the `websocket-client-simple` gem (soft dependency).
      #
      # Usage:
      #   ws = RubyLLM::ResponsesAPI::WebSocket.new(api_key: ENV['OPENAI_API_KEY'])
      #   ws.connect
      #
      #   ws.create_response(model: 'gpt-4o', input: [{ type: 'message', role: 'user', content: 'Hi' }]) do |chunk|
      #     print chunk.content if chunk.content
      #   end
      #
      #   ws.disconnect
      class WebSocket
        WEBSOCKET_PATH = '/v1/responses'
        KNOWN_PARAMS = %i[store metadata compact_threshold context_management].freeze

        attr_reader :last_response_id

        # @param api_key [String] OpenAI API key
        # @param api_base [String] API base URL (https scheme; converted to wss)
        # @param organization_id [String, nil] OpenAI organization ID
        # @param project_id [String, nil] OpenAI project ID
        # @param client_class [#connect, nil] WebSocket client class (for testing)
        def initialize(api_key:, api_base: 'https://api.openai.com/v1', organization_id: nil, project_id: nil,
                       client_class: nil)
          @api_key = api_key
          @api_base = api_base
          @organization_id = organization_id
          @project_id = project_id
          @client_class = client_class

          @ws = nil
          @mutex = Mutex.new
          @connected = false
          @in_flight = false
          @last_response_id = nil
          @message_queue = nil
        end

        # Open the WebSocket connection. Blocks until the connection is established.
        # @param timeout [Numeric] seconds to wait for the connection (default: 10)
        # @raise [ConnectionError] if the connection cannot be established
        # @return [self]
        def connect(timeout: 10)
          client_class = @client_class || resolve_client_class

          ready = Queue.new
          error_holder = []

          @ws = client_class.connect(build_ws_url, headers: build_headers)

          @ws.on(:open) { ready.push(:ok) }

          @ws.on(:error) do |e|
            error_holder << e
            ready.push(:error) unless @connected
          end

          @ws.on(:close) do
            @mutex.synchronize do
              @connected = false
              @message_queue&.push(nil)
            end
          end

          # Route all messages to the current queue (swapped per request)
          @ws.on(:message) do |msg|
            q = @mutex.synchronize { @message_queue }
            q&.push(msg.data)
          end

          result = pop_with_timeout(ready, timeout)
          if result == :error || result.nil?
            err = error_holder.first
            raise ConnectionError, "WebSocket connection failed: #{err&.message || 'timeout'}"
          end

          @mutex.synchronize { @connected = true }
          self
        end

        # Send a response.create request and stream chunks via block.
        # @param model [String] model ID
        # @param input [Array<Hash>] input items in Responses API format
        # @param tools [Array<Hash>, nil] tool definitions
        # @param previous_response_id [String, nil] chain to a prior response
        # @param instructions [String, nil] system/developer instructions
        # @param extra [Hash] additional top-level fields forwarded to the API
        # @yield [RubyLLM::Chunk] each streamed chunk
        # @return [RubyLLM::Message] the assembled final message
        # @raise [ConcurrencyError] if another response is already in flight
        # @raise [ConnectionError] if not connected
        def create_response(model:, input:, tools: nil, previous_response_id: nil, instructions: nil, **extra, &block)
          ensure_connected!
          acquire_flight!

          queue = Queue.new
          @mutex.synchronize { @message_queue = queue }

          payload = build_payload(
            model: model, input: input, tools: tools,
            previous_response_id: previous_response_id,
            instructions: instructions, **extra
          )

          send_json(payload)
          accumulate_response(queue, &block)
        ensure
          @mutex.synchronize { @message_queue = nil }
          release_flight!
        end

        # Warm up the connection by sending a response.create with generate: false.
        # Caches model weights server-side without generating output.
        # @param model [String] model ID
        # @param extra [Hash] additional fields
        # @return [void]
        def warmup(model:, **extra)
          ensure_connected!
          acquire_flight!

          queue = Queue.new
          @mutex.synchronize { @message_queue = queue }

          payload = {
            type: 'response.create',
            response: { model: model, generate: false }.merge(extra)
          }

          send_json(payload)

          loop do
            data = queue.pop
            break if data.nil?

            parsed = JSON.parse(data)
            event_type = parsed['type']

            if event_type == 'error'
              error_msg = parsed.dig('error', 'message') || 'Warmup error'
              raise ResponseError, error_msg
            end

            break if event_type == 'response.completed'
          end
        ensure
          @mutex.synchronize { @message_queue = nil }
          release_flight!
        end

        # Disconnect the WebSocket.
        # @return [void]
        def disconnect
          @ws&.close
          @mutex.synchronize { @connected = false }
        end

        # @return [Boolean]
        def connected?
          @mutex.synchronize { @connected }
        end

        # Close and reopen the connection.
        # @return [self]
        def reconnect(timeout: 10)
          disconnect
          connect(timeout: timeout)
        end

        # Custom error types
        class ConnectionError < StandardError; end
        class ConcurrencyError < StandardError; end
        class ResponseError < StandardError; end

        private

        def resolve_client_class
          require 'websocket-client-simple'
          ::WebSocket::Client::Simple
        rescue LoadError
          raise LoadError,
                'The websocket-client-simple gem is required for WebSocket mode. ' \
                "Add `gem 'websocket-client-simple'` to your Gemfile."
        end

        def build_ws_url
          base = @api_base.sub(%r{/v1\z}, '')
          host = base.sub(%r{\Ahttps?://}, '')
          "wss://#{host}#{WEBSOCKET_PATH}"
        end

        def build_headers
          headers = {
            'Authorization' => "Bearer #{@api_key}",
            'OpenAI-Beta' => 'responses.websocket=v1'
          }
          headers['OpenAI-Organization'] = @organization_id if @organization_id
          headers['OpenAI-Project'] = @project_id if @project_id
          headers
        end

        def build_payload(model:, input:, tools: nil, previous_response_id: nil, instructions: nil, **extra)
          prev_id = previous_response_id || @last_response_id
          response = { model: model, input: input }
          response[:tools] = tools.map { |t| Tools.tool_for(t) } if tools&.any?
          response[:previous_response_id] = prev_id if prev_id
          response[:instructions] = instructions if instructions

          State.apply_state_params(response, extra)
          Compaction.apply_compaction(response, extra)

          forwarded = extra.reject { |k, _| KNOWN_PARAMS.include?(k) }
          { type: 'response.create', response: response.merge(forwarded) }
        end

        def send_json(payload)
          @ws.send(JSON.generate(payload))
        end

        def accumulate_response(queue, &block)
          accumulator = StreamAccumulator.new

          loop do
            raw = queue.pop
            break if raw.nil?

            data = JSON.parse(raw)
            event_type = data['type']

            chunk = Streaming.build_chunk(data)
            accumulator.add(chunk)
            block&.call(chunk)

            if event_type == 'response.completed'
              track_response_id(data)
              break
            end
          end

          build_final_message(accumulator)
        end

        def track_response_id(data)
          resp_id = data.dig('response', 'id')
          @mutex.synchronize { @last_response_id = resp_id } if resp_id
        end

        def build_final_message(accumulator)
          Message.new(
            role: :assistant,
            content: accumulator.content,
            tool_calls: accumulator.tool_calls.empty? ? nil : accumulator.tool_calls,
            model_id: accumulator.model_id,
            response_id: @last_response_id
          )
        end

        def ensure_connected!
          raise ConnectionError, 'WebSocket is not connected. Call #connect first.' unless connected?
        end

        def acquire_flight!
          @mutex.synchronize do
            raise ConcurrencyError, 'Another response is already in flight.' if @in_flight

            @in_flight = true
          end
        end

        def release_flight!
          @mutex.synchronize { @in_flight = false }
        end

        def pop_with_timeout(queue, seconds)
          Timeout.timeout(seconds) { queue.pop }
        rescue Timeout::Error
          nil
        end
      end
    end
  end
end

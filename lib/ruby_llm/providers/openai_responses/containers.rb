# frozen_string_literal: true

module RubyLLM
  module Providers
    class OpenAIResponses
      # Containers API support for managing persistent execution environments.
      # Containers can be used with the shell tool and code interpreter.
      module Containers
        module_function

        # URL helpers
        def containers_url
          'containers'
        end

        def container_url(container_id)
          "containers/#{container_id}"
        end

        def container_files_url(container_id)
          "containers/#{container_id}/files"
        end

        def container_file_url(container_id, file_id)
          "containers/#{container_id}/files/#{file_id}"
        end

        def container_file_content_url(container_id, file_id)
          "containers/#{container_id}/files/#{file_id}/content"
        end

        # Build create container payload
        # @param name [String, nil] Name for the container
        # @param expires_after [Hash, nil] Expiry config, e.g. { anchor: 'last_active_at', minutes: 60 }
        # @param file_ids [Array<String>, nil] Files to copy into the container
        # @param memory_limit [String, nil] Memory limit: '1g', '4g', '16g', '64g'
        # @return [Hash] Create container payload
        def create_payload(name: nil, expires_after: nil, file_ids: nil, memory_limit: nil)
          payload = {}
          payload[:name] = name if name
          payload[:expires_after] = expires_after if expires_after
          payload[:file_ids] = file_ids if file_ids
          payload[:memory_limit] = memory_limit if memory_limit
          payload
        end
      end
    end
  end
end

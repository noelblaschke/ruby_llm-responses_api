# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubyLLM::Providers::OpenAIResponses::Containers do
  let(:containers) { RubyLLM::Providers::OpenAIResponses::Containers }

  describe 'URL helpers' do
    it 'returns containers base URL' do
      expect(containers.containers_url).to eq('containers')
    end

    it 'returns container URL with ID' do
      expect(containers.container_url('cntr_abc')).to eq('containers/cntr_abc')
    end

    it 'returns container files URL' do
      expect(containers.container_files_url('cntr_abc')).to eq('containers/cntr_abc/files')
    end

    it 'returns container file URL' do
      expect(containers.container_file_url('cntr_abc', 'file_123')).to eq('containers/cntr_abc/files/file_123')
    end

    it 'returns container file content URL' do
      expect(containers.container_file_content_url('cntr_abc', 'file_123'))
        .to eq('containers/cntr_abc/files/file_123/content')
    end
  end

  describe '.create_payload' do
    it 'returns empty hash with no options' do
      expect(containers.create_payload).to eq({})
    end

    it 'includes name when provided' do
      payload = containers.create_payload(name: 'my-container')
      expect(payload[:name]).to eq('my-container')
    end

    it 'includes expires_after when provided' do
      expiry = { anchor: 'last_active_at', minutes: 60 }
      payload = containers.create_payload(expires_after: expiry)
      expect(payload[:expires_after]).to eq(expiry)
    end

    it 'includes file_ids when provided' do
      payload = containers.create_payload(file_ids: %w[file_1 file_2])
      expect(payload[:file_ids]).to eq(%w[file_1 file_2])
    end

    it 'includes memory_limit when provided' do
      payload = containers.create_payload(memory_limit: '4g')
      expect(payload[:memory_limit]).to eq('4g')
    end

    it 'includes all options together' do
      payload = containers.create_payload(
        name: 'test',
        expires_after: { anchor: 'last_active_at', minutes: 30 },
        file_ids: ['file_1'],
        memory_limit: '16g'
      )

      expect(payload.keys).to contain_exactly(:name, :expires_after, :file_ids, :memory_limit)
    end
  end

  describe 'namespace access' do
    it 'is accessible via RubyLLM::ResponsesAPI::Containers' do
      expect(RubyLLM::ResponsesAPI::Containers).to eq(containers)
    end
  end
end

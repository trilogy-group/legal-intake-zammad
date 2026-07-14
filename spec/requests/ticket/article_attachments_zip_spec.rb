# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

require 'rails_helper'

RSpec.describe 'Ticket Article Attachments Zip Download', authenticated_as: -> { agent }, type: :request do

  let(:group) { create(:group) }
  let(:agent) do
    create(:agent, groups: [Group.lookup(name: 'Users'), group])
  end

  let(:ticket)   { create(:ticket, group: group) }
  let(:article1) { create(:ticket_article, ticket: ticket) }
  let(:article2) { create(:ticket_article, ticket: ticket) }

  before do
    create(:store,
           object:      'Ticket::Article',
           o_id:        article1.id,
           data:        'content of file one',
           filename:    'file1.txt',
           preferences: { 'Content-Type' => 'text/plain' })
    create(:store,
           object:      'Ticket::Article',
           o_id:        article2.id,
           data:        'content of file two',
           filename:    'file2.txt',
           preferences: { 'Content-Type' => 'text/plain' })
  end

  def unzip(body)
    entries = {}
    Zip::InputStream.open(StringIO.new(body)) do |io|
      while (entry = io.get_next_entry)
        entries[entry.name] = io.read
      end
    end
    entries
  end

  describe 'GET /api/v1/ticket_attachment_zip/:ticket_id' do
    it 'returns a zip response', :aggregate_failures do
      get "/api/v1/ticket_attachment_zip/#{ticket.id}", params: {}

      expect(response).to have_http_status(:ok)
      expect(response.headers['Content-Type']).to include('application/zip')
      expect(response.headers['Content-Disposition']).to include('attachment')
    end

    it 'includes every article attachment with its content' do
      get "/api/v1/ticket_attachment_zip/#{ticket.id}", params: {}

      expect(unzip(response.body)).to eq(
        'file1.txt' => 'content of file one',
        'file2.txt' => 'content of file two',
      )
    end

    it 'sets a restrictive CSP for the download' do
      get "/api/v1/ticket_attachment_zip/#{ticket.id}", params: {}

      expect(response.headers['Content-Security-Policy']).to eq("default-src 'none'")
    end

    it 'names the file with the ticket sequence number (system_id prefix stripped)' do
      system_id = Setting.get('system_id').to_s
      sequence  = ticket.number.to_s.delete_prefix(system_id).sub(%r{\A0+}, '')

      get "/api/v1/ticket_attachment_zip/#{ticket.id}", params: {}

      expect(response.headers['Content-Disposition']).to include("ticket-#{sequence}-attachments.zip")
    end

    context 'when the ticket has no downloadable attachments' do
      let(:empty_ticket) { create(:ticket, group: group) }

      before { create(:ticket_article, ticket: empty_ticket) }

      it 'returns unprocessable entity' do
        get "/api/v1/ticket_attachment_zip/#{empty_ticket.id}", params: {}

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context 'when the agent has no access to the ticket group' do
      let(:other_group)   { create(:group) }
      let(:other_ticket)  { create(:ticket, group: other_group) }
      let(:other_article) { create(:ticket_article, ticket: other_ticket) }

      before do
        create(:store,
               object:      'Ticket::Article',
               o_id:        other_article.id,
               data:        'secret',
               filename:    'secret.txt',
               preferences: { 'Content-Type' => 'text/plain' })
      end

      it 'is forbidden' do
        get "/api/v1/ticket_attachment_zip/#{other_ticket.id}", params: {}

        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'with duplicate filenames across articles' do
      before do
        create(:store,
               object:      'Ticket::Article',
               o_id:        article2.id,
               data:        'second file, same name',
               filename:    'file1.txt',
               preferences: { 'Content-Type' => 'text/plain' })
      end

      it 'disambiguates duplicate names so no file is lost', :aggregate_failures do
        get "/api/v1/ticket_attachment_zip/#{ticket.id}", params: {}

        entries = unzip(response.body)
        expect(entries.keys).to include('file1.txt', 'file1 (1).txt')
        expect(entries.values).to include('content of file one', 'second file, same name')
      end
    end
  end

  describe 'GET /api/v1/ticket_attachment_zip_by_article/:article_id' do
    it 'returns a zip of only that article\'s attachments' do
      get "/api/v1/ticket_attachment_zip_by_article/#{article1.id}", params: {}

      expect(unzip(response.body)).to eq('file1.txt' => 'content of file one')
    end

    it 'names the file with the ticket sequence number and "comment"' do
      system_id = Setting.get('system_id').to_s
      sequence  = ticket.number.to_s.delete_prefix(system_id).sub(%r{\A0+}, '')

      get "/api/v1/ticket_attachment_zip_by_article/#{article1.id}", params: {}

      expect(response.headers['Content-Disposition'])
        .to include("ticket-#{sequence}-comment-#{article1.id}-attachments.zip")
    end

    context 'when the agent has no access to the ticket group' do
      let(:other_group)   { create(:group) }
      let(:other_ticket)  { create(:ticket, group: other_group) }
      let(:other_article) { create(:ticket_article, ticket: other_ticket) }

      before do
        create(:store,
               object:      'Ticket::Article',
               o_id:        other_article.id,
               data:        'secret',
               filename:    'secret.txt',
               preferences: { 'Content-Type' => 'text/plain' })
      end

      it 'is forbidden' do
        get "/api/v1/ticket_attachment_zip_by_article/#{other_article.id}", params: {}

        expect(response).to have_http_status(:forbidden)
      end
    end
  end
end

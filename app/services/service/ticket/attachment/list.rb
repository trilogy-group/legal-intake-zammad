# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

# Collects the user-facing attachments of a ticket, matching exactly what the
# ticket "Attachments" sidebar shows: deduplicated by underlying file, with
# inline (embedded) images and internal "original-format" copies removed.
#
# Shared by Gql::Queries::Ticket::Attachments (the sidebar list) and the
# "download all as zip" endpoints, so the zip contents always match the list.
class Service::Ticket::Attachment::List < Service::BaseWithCurrentUser
  # All visible, downloadable attachments across every article of the ticket
  # the current user may read.
  def execute(ticket:)
    articles = Service::Ticket::Article::List
      .new(current_user:)
      .execute(ticket:)

    filter(articles)
  end

  # Same filtering, scoped to a single article. Authorization of the article
  # (and its ticket) is the caller's responsibility.
  def execute_for_article(article:)
    filter([article])
  end

  private

  def filter(articles)
    return [] if articles.blank?

    inline_attachments = articles.map { |x| x.attachments_inline.map(&:id) }.flatten.uniq

    articles
      .map(&:attachments)
      .flatten
      .reject { |f| inline_attachment?(inline_attachments, f) || original_format?(f) }
      .uniq(&:store_file_id)
      .sort_by(&:created_at).reverse
  end

  def inline_attachment?(inline_attachments, file)
    inline_attachments.include?(file.id)
  end

  def original_format?(file)
    return false if file.preferences.blank?
    return false if !file.preferences.key?('original-format')
    return false if file.preferences['original-format'].blank?

    file.preferences['original-format']
  end
end

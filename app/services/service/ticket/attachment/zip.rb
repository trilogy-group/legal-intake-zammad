# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

require 'zip'

# Builds a single ZIP archive from a list of Store records, streaming each
# file's content into the archive. Handles duplicate filenames by suffixing
# " (1)", " (2)", ... so no entry is silently overwritten.
class Service::Ticket::Attachment::Zip < Service::Base
  # @param stores [Array<Store>] the attachments to include
  def initialize(stores)
    super()
    @stores = stores
  end

  # @return [String] the raw bytes of the ZIP archive
  def execute
    buffer = Zip::OutputStream.write_buffer do |zip|
      used_names = {}
      @stores.each do |store|
        name = unique_name(used_names, store.filename)
        zip.put_next_entry(name)
        zip.write(store.content)
      end
    end

    buffer.rewind
    buffer.read
  end

  private

  def unique_name(used_names, filename)
    filename = filename.presence || 'attachment'

    count = used_names[filename]
    if count.nil?
      used_names[filename] = 0
      return filename
    end

    count += 1
    used_names[filename] = count

    ext  = File.extname(filename)
    base = File.basename(filename, ext)
    candidate = "#{base} (#{count})#{ext}"

    # Guard against a manufactured name colliding with a real one.
    candidate = "#{base} (#{count += 1})#{ext}" while used_names.key?(candidate)
    used_names[candidate] = 0
    candidate
  end
end

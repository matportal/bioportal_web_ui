class MobiSyncAllJob < ApplicationJob
  queue_as :default

  def perform
    Mobi::OntologySyncService.new(full_sync: true).call
  end
end

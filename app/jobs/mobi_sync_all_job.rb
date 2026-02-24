class MobiSyncAllJob < ApplicationJob
  queue_as :default

  def perform
    Mobi::OntologySyncService.call(full_sync: true)
  end
end

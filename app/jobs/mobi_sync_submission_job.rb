class MobiSyncSubmissionJob < ApplicationJob
  queue_as :default

  def perform(acronym:, submission_id: nil)
    Mobi::OntologySyncService.call(acronym: acronym, submission_id: submission_id)
  end
end

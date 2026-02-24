class MobiSyncSubmissionJob < ApplicationJob
  queue_as :default

  def perform(acronym:, submission_id: nil)
    Mobi::OntologySyncService.new(acronym: acronym, submission_id: submission_id).call
  end
end

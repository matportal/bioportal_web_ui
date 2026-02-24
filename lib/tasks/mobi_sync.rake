namespace :mobi do
  desc "Sync a single ontology submission to Mobi. Usage: rake mobi:sync_submission[ACRONYM,SUBMISSION_ID]"
  task :sync_submission, [:acronym, :submission_id] => :environment do |_t, args|
    acronym = args[:acronym].to_s.strip
    raise ArgumentError, "ACRONYM is required" if acronym.blank?

    submission_id = args[:submission_id].presence&.to_i
    result = Mobi::OntologySyncService.new(acronym: acronym, submission_id: submission_id).call
    puts result.to_json
  end

  desc "Sync all MatPortal ontologies to Mobi using each ontology's latest submission"
  task sync_all: :environment do
    result = Mobi::OntologySyncService.new(full_sync: true).call
    puts result.to_json
  end
end

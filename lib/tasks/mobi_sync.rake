namespace :mobi do
  desc "Sync a single ontology submission to Mobi. Usage: rake mobi:sync_submission[ACRONYM,SUBMISSION_ID]"
  task :sync_submission, [:acronym, :submission_id] => :environment do |_t, args|
    acronym = args[:acronym].to_s.strip
    raise ArgumentError, "ACRONYM is required" if acronym.blank?

    submission_id = args[:submission_id].presence&.to_i
    result = Mobi::OntologySyncService.call(acronym: acronym, submission_id: submission_id)
    puts result.to_json
  end

  desc "Sync all MatPortal ontologies to Mobi using each ontology's latest submission"
  task sync_all: :environment do
    result = Mobi::OntologySyncService.call(full_sync: true)
    puts result.to_json
  end
end

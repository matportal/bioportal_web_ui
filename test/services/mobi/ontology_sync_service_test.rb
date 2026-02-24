# frozen_string_literal: true

require "test_helper"
require "cgi"

class MobiOntologySyncServiceTest < ActiveSupport::TestCase
  setup do
    Rails.cache.clear
    @rest_url = LinkedData::Client.settings.rest_url.to_s.chomp("/")
    @mobi_base = "https://mobi.example.org"
  end

  test "creates a new ontology record in mobi when no record exists" do
    with_env(
      "MOBI_SYNC_ENABLED" => "true",
      "MOBI_BASE_URL" => @mobi_base,
      "MOBI_SYNC_USERNAME" => "matportal-sync-test",
      "MOBI_SYNC_EMAIL" => "sync@test.local"
    ) do
      acronym = "NEWONT"
      submission_id = 7
      download_url = "#{@rest_url}/ontologies/#{acronym}/submissions/#{submission_id}/download"

      stub_snapshot_requests(acronym, submission_id, download_url)
      stub_catalog_lookup
      stub_record_search(acronym, [], "http://mobi.example.org/catalogs/local")
      stub_request(:post, "#{@mobi_base}/mobirest/ontologies")
        .to_return(status: 201, body: {
          recordId: "http://mobi.example.org/records/#{acronym}",
          branchId: "http://mobi.example.org/branches/master",
          commitId: "http://mobi.example.org/commits/1"
        }.to_json)

      result = Mobi::OntologySyncService.new(acronym: acronym, submission_id: submission_id).call

      assert_equal "created", result[:status]
      assert_equal acronym, result[:acronym]
      assert_equal submission_id, result[:submission_id]
      assert_equal "http://mobi.example.org/records/#{acronym}", result[:record_id]
      assert_requested(:post, "#{@mobi_base}/mobirest/ontologies", times: 1)
    end
  end

  test "updates an existing ontology through branch, merge request, and auto-accept" do
    with_env(
      "MOBI_SYNC_ENABLED" => "true",
      "MOBI_BASE_URL" => @mobi_base,
      "MOBI_SYNC_USERNAME" => "matportal-sync-test",
      "MOBI_SYNC_EMAIL" => "sync@test.local"
    ) do
      acronym = "UPDONT"
      submission_id = 9
      catalog_id = "http://mobi.example.org/catalogs/local"
      record_id = "http://mobi.example.org/records/updont"
      master_branch_id = "http://mobi.example.org/branches/master"
      master_head_commit = "http://mobi.example.org/commits/master-head"
      feature_branch_id = "http://mobi.example.org/branches/updont-sync-9"
      merge_request_id = "http://mobi.example.org/merge-requests/123"
      download_url = "#{@rest_url}/ontologies/#{acronym}/submissions/#{submission_id}/download"

      stub_snapshot_requests(acronym, submission_id, download_url)
      stub_catalog_lookup(catalog_id: catalog_id)
      stub_record_search(acronym, [
                           {
                             "@id" => record_id,
                             "http://purl.org/dc/terms/title" => [{ "@value" => acronym }]
                           }
                         ], catalog_id)

      stub_request(:get, "#{@mobi_base}/mobirest/catalogs/#{CGI.escape(catalog_id)}/records/#{CGI.escape(record_id)}/branches/master")
        .to_return(status: 200, body: {
          "@id" => master_branch_id,
          "@type" => ["http://mobi.com/ontologies/catalog#MasterBranch"],
          "http://mobi.com/ontologies/catalog#head" => [{ "@id" => master_head_commit }]
        }.to_json)

      stub_merge_request_search(record_id, "accepted")
      stub_merge_request_search(record_id, "open")

      stub_request(:delete, "#{@mobi_base}/mobirest/catalogs/#{CGI.escape(catalog_id)}/records/#{CGI.escape(record_id)}/in-progress-commit")
        .to_return(status: 204, body: "")

      stub_request(:post, "#{@mobi_base}/mobirest/catalogs/#{CGI.escape(catalog_id)}/records/#{CGI.escape(record_id)}/branches")
        .to_return(status: 201, body: feature_branch_id)

      stub_request(:put, %r{\A#{Regexp.escape(@mobi_base)}/mobirest/ontologies/#{Regexp.escape(CGI.escape(record_id))}\?})
        .to_return(status: 200, body: "")

      stub_request(:post, %r{\A#{Regexp.escape(@mobi_base)}/mobirest/catalogs/#{Regexp.escape(CGI.escape(catalog_id))}/records/#{Regexp.escape(CGI.escape(record_id))}/branches/.*/commits\?})
        .to_return(status: 201, body: "http://mobi.example.org/commits/789")

      stub_request(:post, "#{@mobi_base}/mobirest/merge-requests")
        .to_return(status: 201, body: merge_request_id)

      stub_request(:post, "#{@mobi_base}/mobirest/merge-requests/#{CGI.escape(merge_request_id)}/status?action=accept")
        .to_return(status: 200, body: "")

      result = Mobi::OntologySyncService.new(acronym: acronym, submission_id: submission_id).call

      assert_equal "accepted", result[:status]
      assert_equal acronym, result[:acronym]
      assert_equal submission_id, result[:submission_id]
      assert_equal merge_request_id, result[:merge_request_id]
      assert_requested(:post, "#{@mobi_base}/mobirest/merge-requests", times: 1,
                       headers: { "X-Forwarded-Preferred-Username" => "matportal-sync-test" })
      assert_requested(:post, "#{@mobi_base}/mobirest/merge-requests/#{CGI.escape(merge_request_id)}/status?action=accept", times: 1)
    end
  end

  private

  def stub_snapshot_requests(acronym, submission_id, download_url)
    stub_request(:get, "#{@rest_url}/ontologies/#{acronym}")
      .with(query: hash_including("include" => "acronym,name,links,viewOf"))
      .to_return(status: 200, body: {
        acronym: acronym,
        name: "Ontology #{acronym}",
        links: {
          latest_submission: "#{@rest_url}/ontologies/#{acronym}/latest_submission"
        }
      }.to_json)

    stub_request(:get, "#{@rest_url}/ontologies/#{acronym}/submissions/#{submission_id}")
      .with(query: hash_including("include" => "submissionId,version,links"))
      .to_return(status: 200, body: {
        submissionId: submission_id,
        version: "v#{submission_id}",
        links: { download: download_url }
      }.to_json)

    stub_request(:get, download_url)
      .to_return(status: 200, body: "ontology-content-#{acronym}")
  end

  def stub_catalog_lookup(catalog_id: "http://mobi.example.org/catalogs/local")
    stub_request(:get, "#{@mobi_base}/mobirest/catalogs")
      .to_return(status: 200, body: [
        {
          "@id" => catalog_id,
          "http://purl.org/dc/terms/title" => [{ "@value" => "Mobi Catalog (Local)" }]
        }
      ].to_json)
  end

  def stub_record_search(acronym, records, catalog_id)
    stub_request(:get, "#{@mobi_base}/mobirest/catalogs/#{CGI.escape(catalog_id)}/records")
      .with(query: hash_including(
              "searchText" => acronym,
              "type" => "http://mobi.com/ontologies/ontology-editor#OntologyRecord"
            ))
      .to_return(status: 200, body: records.to_json)
  end

  def stub_merge_request_search(record_id, status)
    stub_request(:get, "#{@mobi_base}/mobirest/merge-requests")
      .with(query: hash_including("requestStatus" => status, "records" => record_id))
      .to_return(status: 200, body: [].to_json)
  end

  def with_env(vars)
    previous = vars.keys.index_with { |key| ENV[key] }
    vars.each { |key, value| ENV[key] = value }
    yield
  ensure
    previous.each { |key, value| ENV[key] = value }
  end
end

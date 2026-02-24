# frozen_string_literal: true

require "base64"
require "cgi"
require "json"
require "openssl"
require "rest-client"
require "tempfile"
require "time"

module Mobi
  class OntologySyncService < ApplicationService
    ONTOLOGY_RECORD_TYPE = "http://mobi.com/ontologies/ontology-editor#OntologyRecord"
    CATALOG_BRANCH_TYPE = "http://mobi.com/ontologies/catalog#Branch"
    CATALOG_HEAD_PREDICATE = "http://mobi.com/ontologies/catalog#head"
    CATALOG_MASTER_BRANCH_TYPE = "http://mobi.com/ontologies/catalog#MasterBranch"
    DCTERMS_ISSUED = "http://purl.org/dc/terms/issued"
    DCTERMS_TITLE = "http://purl.org/dc/terms/title"
    LOCAL_CATALOG_TITLE = "Mobi Catalog (Local)"
    PAGE_SIZE = 200

    Snapshot = Struct.new(:acronym, :name, :submission_id, :version, :download_url, keyword_init: true)

    def initialize(acronym: nil, submission_id: nil, full_sync: false, logger: Rails.logger)
      @acronym = acronym&.to_s&.upcase
      @submission_id = submission_id&.to_i
      @full_sync = full_sync
      @logger = logger
      @mobi_catalog_id = nil
    end

    def call
      return { status: "skipped", reason: "disabled" } unless self.class.enabled?

      if @full_sync
        sync_all
      else
        raise ArgumentError, "acronym is required when full_sync is false" if @acronym.blank?

        sync_single(@acronym, @submission_id)
      end
    rescue StandardError => e
      log_error("Mobi ontology sync failed", e)
      { status: "error", error: e.message }
    end

    def self.enabled?
      truthy_env?(ENV.fetch("MOBI_SYNC_ENABLED", "false"))
    end

    def self.truthy_env?(value)
      value.to_s.match?(/\A(true|1|yes|on)\z/i)
    end

    private

    def sync_all
      results = []
      list_snapshots.each do |snapshot|
        results << sync_snapshot(snapshot)
      rescue StandardError => e
        log_error("Mobi sync failed for ontology #{snapshot&.acronym}", e)
        results << { status: "error", acronym: snapshot&.acronym, error: e.message }
      end

      {
        status: "ok",
        mode: "full_sync",
        total: results.length,
        synced: results.count { |r| %w[created accepted accepted_existing_open already_synced no_changes].include?(r[:status]) },
        failed: results.count { |r| r[:status] == "error" },
        results: results
      }
    end

    def sync_single(acronym, submission_id)
      snapshot = fetch_snapshot_for(acronym, submission_id)
      return { status: "skipped", reason: "no_snapshot", acronym: acronym } if snapshot.nil?

      sync_snapshot(snapshot)
    end

    def sync_snapshot(snapshot)
      record_id = find_record_id(snapshot.acronym) || create_record(snapshot)
      return { status: "created", acronym: snapshot.acronym, submission_id: snapshot.submission_id, record_id: record_id } if record_recently_created?(snapshot.acronym, snapshot.submission_id)

      catalog_id = mobi_catalog_id
      master_branch = fetch_master_branch(record_id, catalog_id)
      marker = "[MatPortal #{snapshot.acronym} submission #{snapshot.submission_id}]"

      accepted_mr = find_merge_request(record_id, marker, "accepted")
      if accepted_mr
        cache_sync_state(snapshot.acronym, record_id, snapshot.submission_id)
        return { status: "already_synced", acronym: snapshot.acronym, submission_id: snapshot.submission_id, merge_request_id: accepted_mr }
      end

      open_mr = find_merge_request(record_id, marker, "open")
      if open_mr
        accept_merge_request(open_mr)
        cache_sync_state(snapshot.acronym, record_id, snapshot.submission_id)
        return { status: "accepted_existing_open", acronym: snapshot.acronym, submission_id: snapshot.submission_id, merge_request_id: open_mr }
      end

      ontology_file = download_submission_file(snapshot.download_url, snapshot.acronym)
      clear_in_progress_commit(record_id, catalog_id)
      branch_id = create_branch(record_id, catalog_id, master_branch[:head_commit_id], snapshot, marker)

      upload_status = upload_changes(record_id, branch_id, master_branch[:head_commit_id], ontology_file)
      if upload_status == 204
        cache_sync_state(snapshot.acronym, record_id, snapshot.submission_id)
        return { status: "no_changes", acronym: snapshot.acronym, submission_id: snapshot.submission_id, record_id: record_id }
      end

      commit_id = create_branch_commit(record_id, catalog_id, branch_id, snapshot)
      merge_request_id = create_merge_request(record_id, branch_id, master_branch[:branch_id], snapshot, marker)
      accept_merge_request(merge_request_id)
      cache_sync_state(snapshot.acronym, record_id, snapshot.submission_id)

      {
        status: "accepted",
        acronym: snapshot.acronym,
        submission_id: snapshot.submission_id,
        record_id: record_id,
        branch_id: branch_id,
        commit_id: commit_id,
        merge_request_id: merge_request_id
      }
    ensure
      ontology_file&.close!
    end

    def list_snapshots
      snapshots = []
      each_ontoportal_ontology do |ontology|
        acronym = ontology["acronym"]&.to_s&.upcase
        next if acronym.blank?
        next if ontology["viewOf"].present?

        latest_submission_url = extract_link(ontology, "latest_submission")
        next if latest_submission_url.blank?

        submission = ontoportal_get_json(latest_submission_url)
        snapshot = snapshot_from_payload(acronym, ontology["name"], submission)
        snapshots << snapshot if snapshot
      end
      snapshots
    end

    def each_ontoportal_ontology
      page = 1
      loop do
        payload = ontoportal_get_json(
          "/ontologies",
          params: {
            page: page,
            pagesize: PAGE_SIZE,
            include: "acronym,name,viewOf,links"
          }
        )
        collection = extract_collection(payload)
        break if collection.empty?

        collection.each { |ontology| yield ontology }
        break if collection.length < PAGE_SIZE

        page += 1
      end
    end

    def fetch_snapshot_for(acronym, submission_id)
      ontology_payload = ontoportal_get_json("/ontologies/#{CGI.escape(acronym)}", params: { include: "acronym,name,links,viewOf" })
      return nil if ontology_payload.nil? || ontology_payload["viewOf"].present?

      submission_payload =
        if submission_id.present?
          ontoportal_get_json("/ontologies/#{CGI.escape(acronym)}/submissions/#{submission_id}",
                              params: { include: "submissionId,version,links" })
        else
          latest_url = extract_link(ontology_payload, "latest_submission")
          return nil if latest_url.blank?
          ontoportal_get_json(latest_url)
        end

      if submission_payload.nil? && submission_id.present?
        latest_url = extract_link(ontology_payload, "latest_submission")
        submission_payload = latest_url.present? ? ontoportal_get_json(latest_url) : nil
      end

      snapshot_from_payload(acronym, ontology_payload["name"], submission_payload)
    end

    def snapshot_from_payload(acronym, name, submission_payload)
      return nil if submission_payload.nil?

      submission_id = submission_payload["submissionId"]&.to_i
      return nil if submission_id.nil?

      version = submission_payload["version"].presence || submission_id.to_s
      download_url = extract_link(submission_payload, "download")
      return nil if download_url.blank?

      Snapshot.new(
        acronym: acronym,
        name: name.presence || acronym,
        submission_id: submission_id,
        version: version,
        download_url: download_url
      )
    end

    def find_record_id(acronym)
      cached = cached_record_id(acronym)
      return cached if cached.present? && record_exists?(cached)

      response = mobi_get_json(
        "/catalogs/#{uri_escape(mobi_catalog_id)}/records",
        params: {
          searchText: acronym,
          type: ONTOLOGY_RECORD_TYPE,
          sort: DCTERMS_TITLE,
          ascending: true,
          limit: PAGE_SIZE
        }
      )

      records = response.is_a?(Array) ? response : []
      exact = records.find { |record| jsonld_text_value(record, DCTERMS_TITLE).to_s.casecmp(acronym).zero? }
      record = exact || records.first
      return nil if record.nil?

      record_id = record["@id"]
      cache_record_id(acronym, record_id) if record_id.present?
      record_id
    end

    def record_exists?(record_id)
      mobi_get_json("/catalogs/#{uri_escape(mobi_catalog_id)}/records/#{uri_escape(record_id)}")
      true
    rescue RestClient::NotFound
      false
    end

    def create_record(snapshot)
      file = download_submission_file(snapshot.download_url, snapshot.acronym)
      response = mobi_request(
        method: :post,
        path: "/ontologies",
        payload: {
          title: snapshot.acronym,
          description: "Synced from MatPortal submission #{snapshot.submission_id}",
          file: file
        },
        expected: [201]
      )

      payload = parse_json_body(response.body)
      record_id = payload["recordId"]
      raise "Mobi recordId missing in ontology creation response" if record_id.blank?

      cache_sync_state(snapshot.acronym, record_id, snapshot.submission_id)
      mark_recently_created(snapshot.acronym, snapshot.submission_id)
      record_id
    ensure
      file&.close!
    end

    def create_branch(record_id, catalog_id, head_commit_id, snapshot, marker)
      title = "matportal/#{snapshot.acronym.downcase}/submission-#{snapshot.submission_id}"
      payload = {
        title: title,
        description: marker,
        type: CATALOG_BRANCH_TYPE,
        commitId: head_commit_id
      }
      response = mobi_request(
        method: :post,
        path: "/catalogs/#{uri_escape(catalog_id)}/records/#{uri_escape(record_id)}/branches",
        payload: payload,
        expected: [201]
      )
      response.body.to_s.strip
    rescue RestClient::BadRequest
      retry_title = "#{title}-retry-#{Time.now.utc.to_i}"
      response = mobi_request(
        method: :post,
        path: "/catalogs/#{uri_escape(catalog_id)}/records/#{uri_escape(record_id)}/branches",
        payload: payload.merge(title: retry_title),
        expected: [201]
      )
      response.body.to_s.strip
    end

    def upload_changes(record_id, branch_id, commit_id, file)
      response = mobi_request(
        method: :put,
        path: "/ontologies/#{uri_escape(record_id)}",
        params: { branchId: branch_id, commitId: commit_id },
        payload: { file: file },
        expected: [200, 204]
      )
      response.code.to_i
    end

    def create_branch_commit(record_id, catalog_id, branch_id, snapshot)
      response = mobi_request(
        method: :post,
        path: "/catalogs/#{uri_escape(catalog_id)}/records/#{uri_escape(record_id)}/branches/#{uri_escape(branch_id)}/commits",
        params: { message: "Sync MatPortal #{snapshot.acronym} submission #{snapshot.submission_id}" },
        expected: [201]
      )
      response.body.to_s.strip
    end

    def create_merge_request(record_id, source_branch_id, target_branch_id, snapshot, marker)
      response = mobi_request(
        method: :post,
        path: "/merge-requests",
        payload: {
          title: "#{marker} Update #{snapshot.acronym}",
          description: "Automated sync from MatPortal submission #{snapshot.submission_id}, version #{snapshot.version}",
          recordId: record_id,
          sourceBranchId: source_branch_id,
          targetBranchId: target_branch_id
        },
        expected: [201]
      )
      response.body.to_s.strip
    end

    def accept_merge_request(merge_request_id)
      mobi_request(
        method: :post,
        path: "/merge-requests/#{uri_escape(merge_request_id)}/status",
        params: { action: "accept" },
        payload: nil,
        expected: [200]
      )
    end

    def find_merge_request(record_id, marker, status)
      response = mobi_get_json(
        "/merge-requests",
        params: {
          sort: DCTERMS_ISSUED,
          ascending: false,
          requestStatus: status,
          searchText: marker,
          records: record_id,
          limit: 20
        }
      )
      items = response.is_a?(Array) ? response : []
      items.first&.dig("@id")
    end

    def fetch_master_branch(record_id, catalog_id)
      branch = mobi_get_json("/catalogs/#{uri_escape(catalog_id)}/records/#{uri_escape(record_id)}/branches/master")
      branch_id = branch["@id"]
      head_commit_id = branch.dig(CATALOG_HEAD_PREDICATE, 0, "@id")
      branch_types = Array(branch["@type"])

      unless branch_types.include?(CATALOG_MASTER_BRANCH_TYPE)
        raise "Expected a MasterBranch for record #{record_id}, got #{branch_types.join(', ')}"
      end

      if branch_id.blank? || head_commit_id.blank?
        raise "Master branch is missing head commit for record #{record_id}"
      end

      { branch_id: branch_id, head_commit_id: head_commit_id }
    end

    def clear_in_progress_commit(record_id, catalog_id)
      mobi_request(
        method: :delete,
        path: "/catalogs/#{uri_escape(catalog_id)}/records/#{uri_escape(record_id)}/in-progress-commit",
        payload: nil,
        expected: [200, 204]
      )
    rescue RestClient::NotFound, RestClient::BadRequest
      nil
    end

    def download_submission_file(download_url, acronym)
      response = ontoportal_request(method: :get, url: download_url)
      ext = File.extname(URI.parse(download_url).path)
      ext = ".owl" if ext.blank?
      file = Tempfile.new(["#{acronym.downcase}_submission_", ext], binmode: true)
      file.write(response.body)
      file.flush
      file.rewind
      file
    end

    def mobi_catalog_id
      @mobi_catalog_id ||= begin
        env_catalog = ENV["MOBI_CATALOG_ID"].to_s.strip
        unless env_catalog.blank?
          env_catalog
        else
          catalogs = mobi_get_json("/catalogs")
          catalogs = Array(catalogs)
          local = catalogs.find { |catalog| jsonld_text_value(catalog, DCTERMS_TITLE) == LOCAL_CATALOG_TITLE }
          selected = local || catalogs.first
          id = selected&.dig("@id")
          raise "Could not resolve Mobi catalog id" if id.blank?

          id
        end
      end
    end

    def mobi_get_json(path, params: nil)
      response = mobi_request(method: :get, path: path, params: params, payload: nil, expected: [200])
      parse_json_body(response.body)
    end

    def mobi_request(method:, path:, params: nil, payload:, expected:)
      url = mobi_url(path, params)
      response = RestClient::Request.execute(
        method: method,
        url: url,
        payload: payload,
        headers: mobi_headers,
        verify_ssl: mobi_verify_ssl,
        open_timeout: request_timeout,
        read_timeout: request_timeout
      )
      code = response.code.to_i
      raise "Unexpected Mobi response #{code} for #{method.to_s.upcase} #{url}" unless expected.include?(code)

      response
    end

    def mobi_url(path, params = nil)
      base = mobi_base_url
      rest_prefix = base.end_with?("/mobirest") ? "" : "/mobirest"
      url = "#{base}#{rest_prefix}#{path}"
      return url if params.blank?

      "#{url}?#{URI.encode_www_form(params)}"
    end

    def ontoportal_get_json(path_or_url, params: nil)
      response = ontoportal_request(method: :get, url: path_or_url, params: params)
      parse_json_body(response.body)
    rescue JSON::ParserError
      nil
    end

    def ontoportal_request(method:, url:, params: nil)
      response = RestClient::Request.execute(
        method: method,
        url: ontoportal_url(url, params),
        headers: ontoportal_headers,
        open_timeout: request_timeout,
        read_timeout: request_timeout
      )
      response
    rescue RestClient::ExceptionWithResponse => e
      code = e.http_code || e.response&.code
      body = e.response&.body
      raise "OntoPortal request failed (#{method.to_s.upcase} #{url}) with status #{code}: #{body}"
    end

    def ontoportal_url(path_or_url, params = nil)
      url = path_or_url.start_with?("http://", "https://") ? path_or_url : "#{ontoportal_base_url}#{path_or_url}"
      return url if params.blank?

      "#{url}?#{URI.encode_www_form(params)}"
    end

    def ontoportal_base_url
      @ontoportal_base_url ||= LinkedData::Client.settings.rest_url.to_s.chomp("/")
    end

    def ontoportal_headers
      headers = { accept: :json }
      api_key = LinkedData::Client.settings.apikey.to_s
      headers[:authorization] = "apikey token=#{api_key}" if api_key.present?
      headers
    end

    def mobi_headers
      headers = { accept: :json }
      headers["X-Forwarded-Preferred-Username"] = sync_username
      headers["X-Forwarded-Email"] = sync_email if sync_email.present?
      headers[:authorization] = "Bearer #{sync_bearer_token}"
      headers
    end

    def sync_username
      ENV.fetch("MOBI_SYNC_USERNAME", "matportal-sync")
    end

    def sync_email
      ENV.fetch("MOBI_SYNC_EMAIL", "matportal-sync@dev.local")
    end

    def sync_bearer_token
      env_token = ENV["MOBI_SYNC_BEARER_TOKEN"].to_s.strip
      return env_token if env_token.present?

      sync_token = keycloak_sync_token
      return sync_token if sync_token.present?

      payload = {
        preferred_username: sync_username,
        email: sync_email,
        sub: sync_username,
        exp: (Time.now + 3600).to_i
      }
      encode_fake_jwt(payload)
    end

    def encode_fake_jwt(payload)
      header_segment = Base64.urlsafe_encode64({ alg: "HS256", typ: "JWT" }.to_json, padding: false)
      payload_segment = Base64.urlsafe_encode64(payload.to_json, padding: false)
      "#{header_segment}.#{payload_segment}.ZGV2"
    end

    def keycloak_sync_token
      client_id = ENV["MOBI_SYNC_CLIENT_ID"].to_s.strip
      client_secret = ENV["MOBI_SYNC_CLIENT_SECRET"].to_s.strip
      return nil if client_id.blank? || client_secret.blank?

      cached_token = Rails.cache.read(sync_token_cache_key(client_id)).to_s
      return cached_token if cached_token.present?

      response = RestClient::Request.execute(
        method: :post,
        url: keycloak_token_url,
        payload: {
          grant_type: "client_credentials",
          client_id: client_id,
          client_secret: client_secret
        },
        headers: { accept: :json },
        open_timeout: request_timeout,
        read_timeout: request_timeout
      )

      payload = parse_json_body(response.body)
      token = payload["access_token"].to_s.strip
      raise "Keycloak token endpoint did not return access_token" if token.blank?

      expires_in = payload["expires_in"].to_i
      ttl_seconds = expires_in > 120 ? expires_in - 60 : 60
      Rails.cache.write(sync_token_cache_key(client_id), token, expires_in: ttl_seconds.seconds)
      token
    rescue RestClient::ExceptionWithResponse => e
      code = e.http_code || e.response&.code
      body = e.response&.body.to_s
      raise "Keycloak token request failed (#{code}): #{body}"
    end

    def keycloak_token_url
      @keycloak_token_url ||= begin
        configured = ENV["MOBI_SYNC_TOKEN_URL"].to_s.strip
        if configured.present?
          configured
        else
          keycloak_site = ENV["KEYCLOAK_SITE"].to_s.strip
          keycloak_realm = ENV["KEYCLOAK_REALM"].to_s.strip
          if keycloak_site.present? && keycloak_realm.present?
            "#{keycloak_site.chomp('/')}/realms/#{CGI.escape(keycloak_realm)}/protocol/openid-connect/token"
          else
            raise "MOBI_SYNC_TOKEN_URL is not configured and KEYCLOAK_SITE/KEYCLOAK_REALM are unavailable"
          end
        end
      end
    end

    def sync_token_cache_key(client_id)
      "mobi_sync:keycloak_access_token:#{client_id}"
    end

    def mobi_base_url
      @mobi_base_url ||= begin
        url = ENV["MOBI_BASE_URL"].to_s.strip
        raise "MOBI_BASE_URL is not configured" if url.blank?

        url.chomp("/")
      end
    end

    def request_timeout
      ENV.fetch("MOBI_SYNC_TIMEOUT_SECONDS", "120").to_i
    end

    def mobi_verify_ssl
      if self.class.truthy_env?(ENV.fetch("MOBI_SYNC_SSL_VERIFY", "true"))
        OpenSSL::SSL::VERIFY_PEER
      else
        OpenSSL::SSL::VERIFY_NONE
      end
    end

    def parse_json_body(body)
      return {} if body.blank?

      JSON.parse(body)
    end

    def extract_collection(payload)
      return payload if payload.is_a?(Array)
      return payload["collection"] if payload.is_a?(Hash) && payload["collection"].is_a?(Array)
      return payload["ontologies"] if payload.is_a?(Hash) && payload["ontologies"].is_a?(Array)

      []
    end

    def extract_link(payload, rel)
      links = payload["links"] || {}
      return links[rel] if links[rel].present?

      payload_id = payload["@id"]
      return nil if payload_id.blank?

      "#{payload_id.chomp('/')}/#{rel}"
    end

    def jsonld_text_value(object, predicate)
      values = Array(object[predicate])
      first_value = values.first || {}
      first_value["@value"] || first_value["@id"] || first_value.to_s
    end

    def uri_escape(value)
      CGI.escape(value.to_s)
    end

    def cache_record_id(acronym, record_id)
      Rails.cache.write(record_cache_key(acronym), record_id, expires_in: 30.days)
    end

    def cached_record_id(acronym)
      Rails.cache.read(record_cache_key(acronym))
    end

    def cache_sync_state(acronym, record_id, submission_id)
      cache_record_id(acronym, record_id)
      Rails.cache.write(last_submission_cache_key(acronym), submission_id.to_i, expires_in: 30.days)
    end

    def mark_recently_created(acronym, submission_id)
      Rails.cache.write(recent_create_cache_key(acronym), submission_id.to_i, expires_in: 10.minutes)
    end

    def record_recently_created?(acronym, submission_id)
      Rails.cache.read(recent_create_cache_key(acronym)).to_i == submission_id.to_i
    end

    def record_cache_key(acronym)
      "mobi_sync:record:#{acronym}"
    end

    def last_submission_cache_key(acronym)
      "mobi_sync:last_submission:#{acronym}"
    end

    def recent_create_cache_key(acronym)
      "mobi_sync:recent_create:#{acronym}"
    end

    def log_error(message, exception)
      @logger.error("#{message}: #{exception.class} - #{exception.message}")
      @logger.error(exception.backtrace.join("\n")) if exception.backtrace
    end
  end
end

class SparqlEndpointController < ApplicationController
  layout :determine_layout
  before_action :check_sparql_enabled
  
  include SparqlHelper
  def index
  end

  def edit_sample_queries
    if params[:graph].nil?
      @sample_queries = helpers.get_catalog_sample_queries
    else
      @sample_queries = helpers.get_ontology_sample_queries(params[:graph])
      public_rest_url = ENV.fetch("PUBLIC_API_URL", LinkedData::Client.settings.rest_url).to_s
      rest_url = $REST_URL.to_s
      @graph = params[:graph].to_s
      if !rest_url.empty? && !public_rest_url.empty?
        @graph = @graph.gsub(rest_url, public_rest_url)
      end
    end
    render partial: 'sample_queries_edit_modal',layout: false
  end

  private

  def check_sparql_enabled
    unless helpers.sparql_enabled?
      redirect_to root_path, alert: 'SPARQL endpoint is not available'
    end
  end
end

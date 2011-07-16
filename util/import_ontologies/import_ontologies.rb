#!/usr/bin/env ruby

# API key that is valid on both to/from BioPortal instances
$API_KEY = "24e0e77e-54e0-11e0-9d7b-005056aa3316"

# The BioPortal instance to take ontologies from
$FROM = "http://ncbostage-coremaster1:8080/bioportal"
$FROM_PORT = "8080"

# The BioPortal instance to import ontologies to
$TO = "http://localhost:8080/bioportal"
$TO_PORT = "8080"

# User id for the user who should own each imported ontology, defaults to the first user (admin)
$ONTOLOGY_OWNER = "1"

# Ontology ids to include in the import (leaving commented will import all ontologies)
$INCLUDE_ONTOLOGIES = [ 1506 ]

require 'rubygems'
require 'rexml/document'
require 'open-uri'
require 'rest_client'
require 'optparse'
require 'active_support/core_ext/benchmark'
require 'bioportal/BioPortalRestfulCore'
require 'bioportal/ontology_wrapper'
require 'bioportal/log'
require 'bioportal/remote_file'

class ImportOntologies
 
  REST = BioPortalRestfulCore

  def self.import_ontologies
    setup_from
    
    # Get ontologies array
    if !(defined? $INCLUDE_ONTOLOGIES).nil? && !$INCLUDE_ONTOLOGIES.nil? && !$INCLUDE_ONTOLOGIES.empty?
      ont_list = []
      $INCLUDE_ONTOLOGIES.each do |ont_id|
        if OntologyWrapper.virtual_id?(ont_id)
          ont_list << REST.getLatestOntology(:ontology_virtual_id => ont_id)
        else
          ont_list << REST.getOntology(:ontology_id => ont_id)
        end
      end
    else
      ont_list = REST.getOntologyList
    end
    
    puts "Total onts: #{ont_list.size}"
    
    error_onts = []
    ont_list.each do |ont|
      begin
        setup_from
        ont_full = REST.getOntology(:ontology_id => ont.id)
      
        # Get filename, prefer abbreviation
        filename = ont.abbreviation.nil? ? ont.displayLabel.downcase : ont.abbreviation.downcase
      
        ont_file = RemoteFile.new("#{$FROM}/ontologies/download/#{ont.id}?apikey=#{$API_KEY}", "#{filename}.#{ont.format.downcase}")
        ont_hash = ont_full.to_params_hash
        
        # Add file
        ont_hash["filePath"] = ont_file
        
        # Change user
        ont_hash['userId'] = $ONTOLOGY_OWNER
        
        # Reset status so the ontology will get parsed
        ont_hash['statusId'] = 1
      
        setup_to
        new_ont = REST.createOntology(ont_hash)
        LOG.add :debug, "Ontology created from id #{ont.id} with new id #{new_ont.id}"
      rescue Exception => e
         error_onts << [ ont.id, ont.displayLabel, e.message ]
         puts "Problem: #{e.message}"
      end   
    end
    
    
    
    puts "\n\n\nerrors" unless error_onts.empty?
    error_onts.each { |ont| puts "#{ont[0]}\t#{ont[1]}\t#{ont[2]}" }
    
  end
  
  def self.setup_from
    $REST_URL = $FROM
    $REST_PORT = $FROM_PORT
  end
  
  def self.setup_to
    $REST_URL = $TO
    $REST_PORT = $TO_PORT
  end

  import_ontologies
  
end
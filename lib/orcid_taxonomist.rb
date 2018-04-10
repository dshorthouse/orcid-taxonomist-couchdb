# encoding: utf-8

class OrcidTaxonomist

  ORCID_API = "https://pub.orcid.org/v2.1"
  ORCID_KEYWORDS = ["taxonomy", "taxonomist", "nomenclature", "systematics"]
  GNRD_API = "http://gnrd.globalnames.org/name_finder.json"

  def initialize args
    args.each do |k,v|
      instance_variable_set("@#{k}", v) unless v.nil?
    end
    @config = parse_config
    server = CouchRest.new(@config[:server])
    @db = server.database!(@config[:database])
  end

  def create_design_document
    des = CouchRest::Design.new
    des.name = "taxonomist"
    des.merge!({"language" => "javascript"})
    new_taxonomist_map = "function(doc) { if(doc.status == 0) { emit(null, doc.orcid); } }"
    updated_taxonomist_map = "function(doc) { if(doc.status == 1) { emit(null, doc); } }"
    country_map = "function(doc) { if(doc.country) { emit(doc.country, 1); }}"
    dois_map = "function(doc) { doc.dois && doc.dois.forEach(function(doi) { emit(doi, 1); }); }"
    des.view_by :new_taxonomists_orcid, :map => new_taxonomist_map
    des.view_by :updated_taxonomists, :map => updated_taxonomist_map
    des.view_by :country, :map => country_map, :reduce => "_sum"
    des.view_by :dois, :map => dois_map, :reduce => "_sum"
    des.database = @db
    des.save
  end

  def populate_taxonomists(doi = nil)
    found_orcids = !doi.nil? ? search_orcids_by_doi(doi) : search_orcids_by_keyword
    (found_orcids.to_a - existing_orcids).each do |orcid|
      o = orcid_metadata(orcid)
      doc = {
        "_id" => orcid,
        "orcid" => orcid,
        "given_names" => o[:given_names],
        "family_name" => o[:family_name],
        "other_names" => o[:other_names],
        "country" => o[:country],
        "taxa" => [],
        "dois" => [],
        "orcid_created" => o[:orcid_created],
        "orcid_updated" => o[:orcid_updated],
        "status" => 0
      }
      @db.save_doc(doc)
    end
  end

  def populate_taxa
    new_orcids.each do |o|
      works = orcid_works(o)
      doc = @db.get(o)
      doc[:taxa] = []
      doc[:dois] = []
      if works.size > 0
        doc[:taxa] = gnrd_names(works.map{ |w| w[:title] }.join(" "))
        doc[:dois] = works.map{ |w| w[:doi] }.compact
      end
      doc[:status] = 1
      @db.save_doc(doc)
    end
  end

  def write_csv
    csv_file = File.join(root, 'public', 'taxonomists.csv')
    CSV.open(csv_file, 'w') do |csv|
      csv << ["given_names", "family_name", "orcid", "country", "taxa"]
      output[:entries].each do |entry|
        csv << [entry[:given_names], entry[:family_name], entry[:orcid], entry[:country], entry[:taxa]]
      end
    end
  end

  def write_webpage
    template = File.join(root, 'template', "template.slim")
    web_page = File.join(root, 'public', 'index.html')
    html = Slim::Template.new(template).render(Object.new, output)
    File.open(web_page, 'w') { |file| file.write(html) }
    html
  end

  def delete_taxonomist(orcid)
    doc = @db.get(orcid)
    @db.delete_doc(doc)
  end

  def update_taxonomist(orcid)
    o = orcid_metadata(orcid)
    doc = @db.get(orcid) || { 
      "_id" => orcid, 
      "orcid" => orcid, 
      "status" => 1, 
      "orcid_created" => o[:orcid_created]
    }
    @db.save_doc(update_doc(doc, o))
  end

  def update_taxonomists
    all_taxonomists.each do |row|
      doc = @db.get(row["orcid"])
      o = orcid_metadata(row["orcid"])
      if doc["orcid_updated"] != o[:orcid_updated]
        @db.save_doc(update_doc(doc, o))
      end
    end
  end

  private

  def root
    File.dirname(File.dirname(__FILE__))
  end

  def parse_config
    config = YAML.load_file(@config_file).deep_symbolize_keys!
    env = ENV.key?("ENVIRONMENT") ? ENV["ENVIRONMENT"] : "development"
    config[env.to_sym]
  end

  def orcid_header
    { 'Accept': 'application/orcid+json' }
  end

  def orcid_metadata(orcid)
    orcid_url = "#{ORCID_API}/#{orcid}/person"
    req = Typhoeus.get(orcid_url, headers: orcid_header)
    json = JSON.parse(req.body, symbolize_names: true)
    given_names = json[:name][:"given-names"][:value] rescue nil
    family_name = json[:name][:"family-name"][:value] rescue nil
    other_names = json[:"other-names"][:"other-name"].map{|o| o[:content]} rescue []
    country = json[:addresses][:address][0][:country][:value] rescue nil
    orcid_created = json[:name][:"created-date"][:value] rescue nil
    orcid_updated = json[:"last-modified-date"][:value] rescue nil
    {
      orcid: orcid,
      given_names: given_names,
      family_name: family_name,
      other_names: other_names,
      country: country,
      orcid_created: orcid_created,
      orcid_updated: orcid_updated
    }
  end

  def orcid_works(orcid)
    orcid_url = "#{ORCID_API}/#{orcid}/works"
    req = Typhoeus.get(orcid_url, headers: orcid_header)
    json = JSON.parse(req.body, symbolize_names: true)
    json[:group].map do |a|
      ids = a[:"work-summary"][0][:"external-ids"][:"external-id"] rescue []
      doi = ids.map{ |d| d[:"external-id-value"] if d[:"external-id-type"] == "doi" }
               .compact.first rescue nil
      title = a[:"work-summary"][0][:title][:title][:value] rescue nil
      { title: title, doi: doi }
    end
  end

  def gnrd_names(text)
    begin
      body = { text: text, unique: true }
      req = Typhoeus.post(GNRD_API, body: body, followlocation: true)
      json = JSON.parse(req.body, symbolize_names: true)
      json[:names].map{ |o| o[:scientificName] }.compact.uniq.sort
    rescue
      []
    end
  end

  def search_orcids_by_keyword
    keyword_parameter = URI::encode(ORCID_KEYWORDS.map{ |k| "keyword:#{k}" }.join(" OR "))
    Enumerator.new do |yielder|
      start = 0

      loop do
        orcid_search_url = "#{ORCID_API}/search?q=#{keyword_parameter}&start=#{start}&rows=200"
        req = Typhoeus.get(orcid_search_url, headers: orcid_header)
        results = JSON.parse(req.body, symbolize_names: true)[:result]
        if results.size > 0
          results.map { |item| yielder << item[:"orcid-identifier"][:path] }
          start += 200
        else
          raise StopIteration
        end
      end
    end.lazy
  end

  def search_orcids_by_doi(doi)
    doi_parameter = URI::encode("doi-self:#{doi}")
    Enumerator.new do |yielder|
      start = 0

      loop do
        orcid_search_url = "#{ORCID_API}/search?q=#{doi_parameter}&start=#{start}&rows=50"
        req = Typhoeus.get(orcid_search_url, headers: orcid_header)
        results = JSON.parse(req.body, symbolize_names: true)[:result]
        if results.size > 0
          results.map { |item| yielder << item[:"orcid-identifier"][:path] }
          start += 50
        else
          raise StopIteration
        end
      end
    end.lazy
  end

  def update_doc(doc, o)
    doc["given_names"] = o[:given_names]
    doc["family_name"] = o[:family_name]
    doc["other_names"] = o[:other_names]
    doc["country"] = o[:country]
    doc["orcid_updated"] = o[:orcid_updated]
    doc["taxa"] = []
    doc["dois"] = []
    works = orcid_works(o[:orcid])
    if works.size > 0
      doc["taxa"] = gnrd_names(works.map{ |w| w[:title] }.join(" "))
      doc["dois"] = works.map{ |w| w[:doi] }.compact
    end
    doc
  end

  def new_orcids
    @db.view('taxonomist/by_new_taxonomists_orcid')['rows']
       .map{|t| t["value"]}.compact
  end

  def all_taxonomists
    @db.view('taxonomist/by_updated_taxonomists')['rows']
       .map{|t| t["value"]}.compact
       .sort_alphabetical_by{|k| k["family_name"]}
  end

  def all_dois
    @db.view('taxonomist/by_dois', :group_level => 1)['rows']
       .map{|d| d["key"]}
  end

  def existing_orcids
    @db.all_docs["rows"]
       .map{|d| d["id"] if d["id"][0] != "_"}.compact
  end

  def output
    country_counts = @db.view('taxonomist/by_country', :group_level => 1)['rows']
                        .map{ |t| [t["key"],t["value"]] }.to_h
    country_names = country_counts.keys.map{ |t| [t, IsoCountryCodes.find(t).name] }.to_h
    data = {
      google_analytics: @config[:google_analytics],
      country_counts: country_counts.to_json,
      country_names: country_names.to_json,
      entries: []
    }
    all_taxonomists.each do |row|
      row.symbolize_keys!
      if row[:country]
        code = IsoCountryCodes.find(row[:country])
        row[:country] = code.name if code
      end
      row[:taxa] = row[:taxa].join(", ")
      row[:other_names] = row[:other_names].join("; ")
      data[:entries] << row
    end
    data
  end

end
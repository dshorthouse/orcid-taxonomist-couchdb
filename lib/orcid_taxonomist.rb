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
    new_taxonomist_map = "function(doc) { if(doc.status == 0) { emit(null, doc.orcid); } }"
    updated_taxonomist_map = "function(doc) { if(doc.status == 1) { emit(null, doc); } }"
    des.view_by :new_taxonomists_orcid, :map => new_taxonomist_map
    des.view_by :updated_taxonomists, :map => updated_taxonomist_map
    des.view_by :country, :map => "function(doc) { emit(doc.country, 1); }", :reduce => "_sum"
    des.database = @db
    des.save
  end

  def populate_taxonomists
    (search_orcids.to_a - existing_orcids).each do |orcid|
      o = orcid_metadata(orcid)
      doc = {
        "_id" => orcid,
        "orcid" => orcid,
        "given_names" => o[:given_names],
        "family_name" => o[:family_name],
        "country" => o[:country],
        "orcid_created" => o[:orcid_created],
        "orcid_updated" => o[:orcid_updated],
        "status" => 0,
        "taxa" => []
      }
      @db.save_doc(doc)
    end
  end

  def populate_taxa
    new_orcids.each do |o|
      works = orcid_works(o)
      doc = @db.get(o)
      if works
        doc[:taxa] = gnrd_names(works.join(" "))
      end
      doc[:status] = 1
      @db.save_doc(doc)
    end
  end

  def write_webpage
    country_counts = @db.view('taxonomist/by_country', :group_level => 1)['rows']
                        .map{ |t| [t["key"],t["value"]] }.to_h
    country_names = country_counts.keys.map{ |t| [t, IsoCountryCodes.find(t).name] }.to_h
    output = {
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
      output[:entries] << row
    end
    template = File.join(root, 'template', "template.slim")
    web_page = File.join(root, 'public', 'index.html')
    html = Slim::Template.new(template).render(Object.new, output)
    File.open(web_page, 'w') { |file| file.write(html) }
    html
  end

  def update_taxonomists
    all_taxonomists.each do |row|
      doc = @db.get(row["orcid"])
      o = orcid_metadata(row["orcid"])
      if doc["orcid_updated"] != o[:orcid_updated]
        doc["given_names"] = o[:given_names]
        doc["family_name"] = o[:family_name]
        doc["country"] = o[:country]
        doc["orcid_updated"] = o[:orcid_updated]
        works = orcid_works(row["orcid"])
        if works
          doc["taxa"] = gnrd_names(works.join(" "))
        end
        @db.save_doc(doc)
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
    country = json[:addresses][:address][0][:country][:value] rescue nil
    orcid_created = json[:name][:"created-date"][:value] rescue nil
    orcid_updated = json[:"last-modified-date"][:value] rescue nil
    {
      given_names: given_names,
      family_name: family_name,
      country: country,
      orcid_created: orcid_created,
      orcid_updated: orcid_updated
    }
  end

  def orcid_works(orcid)
    orcid_url = "#{ORCID_API}/#{orcid}/works"
    req = Typhoeus.get(orcid_url, headers: orcid_header)
    json = JSON.parse(req.body, symbolize_names: true)
    json[:group].map{ |a| a[:"work-summary"][0][:title][:title][:value] } rescue []
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

  def search_orcids
    keyword_parameter = URI::encode(ORCID_KEYWORDS.map{ |k| "keyword:#{k}" }.join(" OR "))
    Enumerator.new do |yielder|
      start = 1

      loop do
        orcid_search_url = "#{ORCID_API}/search?q=#{keyword_parameter}&start=#{start}&rows=200"
        req = Typhoeus.get(orcid_search_url, headers: orcid_header)
        results = JSON.parse(req.body, symbolize_names: true)[:result]
        if results
          results.map { |item| yielder << item[:"orcid-identifier"][:path] }
          start += 200
        else
          raise StopIteration
        end
      end
    end.lazy
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

  def existing_orcids
    @db.all_docs["rows"]
       .map{|d| d["id"] if d["id"][0] != "_"}.compact
  end

end
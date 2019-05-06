# encoding: utf-8

class OrcidTaxonomist

  ORCID_API = "https://pub.orcid.org/v2.1"
  GNRD_API = "https://gnrd.globalnames.org/name_finder.json"

  def initialize args
    args.each do |k,v|
      instance_variable_set("@#{k}", v) unless v.nil?
    end
    @config = parse_config
    server = CouchRest.new(@config[:server])
    @db = server.database!(@config[:database])
  end

  def create_design_document
    d = CouchRest::Design.new
    d.name = "taxonomist"
    d.merge!({"language" => "javascript"})

    new_taxonomist_map = "function(doc) { if(doc.status == 0) { emit(null, doc.orcid); } }"
    d.view_by :new_taxonomists, :map => new_taxonomist_map

    updated_taxonomist_map = "function(doc) { if(doc.status == 1) { emit(null, doc); } }"
    d.view_by :updated_taxonomists, :map => updated_taxonomist_map

    country_code_sum = "function(doc) { if(doc.status == 1 && doc.country) { emit(doc.country, 1); }}"
    d.view_by :country_code, :map => country_code_sum, :reduce => "_sum"

    d.database = @db
    d.save
  end

  def populate_taxonomists(doi = nil)
    found_orcids = !doi.nil? ? search_orcids_by_doi(doi) : search_orcids_by_keyword
    (found_orcids.to_a - existing_orcids).each do |orcid|
      save_new_orcid(orcid)
    end
  end

  def populate_taxa
    new_taxonomists.each do |o|
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

  def populate_from_file(file)
    orcids = Set.new
    CSV.foreach(file, headers: false, encoding: 'bom|utf-8') do |row|
      if row[0].is_doi?
        search_orcids_by_doi(row[0]).each do |orcid|
          orcids.add(orcid)
        end
      elsif row[0].is_orcid?
        orcids.add(row[0])
      end
    end
    (orcids.to_a - existing_orcids).each do |orcid|
      save_new_orcid(orcid)
    end
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
      puts row["family_name"].strip.green
    end
  end

  def rebuild_taxonomists
    count = all_taxonomists.count
    all_taxonomists.each do |row|
      puts count.to_s.green if count % 10 == 0
      doc = @db.get(row["orcid"])
      o = orcid_metadata(row["orcid"])
      @db.save_doc(update_doc(doc, o))
      count -= 1
    end
  end

  def write_csv
    csv_file = File.join(root, 'public', 'taxonomists.csv')
    CSV.open(csv_file, 'w') do |csv|
      csv << ["given_names", "family_name", "other_names", "orcid", "country_name", "country_code", "taxa", "dois"]
      all_taxonomists.each do |entry|
        csv << [
          entry["given_names"],
          entry["family_name"],
          entry["other_names"].join("; "),
          entry["orcid"],
          entry["country_name"],
          entry["country"],
          entry["taxa"].join("; "),
          entry["dois"].join(", ")
        ]
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
    given_names = json[:name][:"given-names"][:value].strip rescue nil
    family_name = json[:name][:"family-name"][:value].strip rescue nil
    other_names = json[:"other-names"][:"other-name"].map{|o| o[:content].strip } rescue []
    country = json[:addresses][:address][0][:country][:value].strip rescue nil
    country_name = IsoCountryCodes.find(country).name rescue nil
    orcid_created = json[:name][:"created-date"][:value] rescue nil
    orcid_updated = json[:"last-modified-date"][:value] rescue nil
    {
      orcid: orcid,
      given_names: given_names,
      family_name: family_name,
      other_names: other_names,
      country: country,
      country_name: country_name,
      orcid_created: orcid_created,
      orcid_updated: orcid_updated
    }
  end

  def save_new_orcid(orcid)
    o = orcid_metadata(orcid)
    country_name = IsoCountryCodes.find(o[:country]).name rescue nil
    doc = {
      "_id" => orcid,
      "orcid" => orcid,
      "given_names" => o[:given_names],
      "family_name" => o[:family_name],
      "other_names" => o[:other_names],
      "country" => o[:country],
      "country_name" => country_name,
      "taxa" => [],
      "dois" => [],
      "orcid_created" => o[:orcid_created],
      "orcid_updated" => o[:orcid_updated],
      "status" => 0
    }
    @db.save_doc(doc)
  end

  def extract_doi(text)
    regex = /(10[.][0-9]{4,}(?:[.][0-9]+)*\/(?:(?![%"#?{} ])\S)+)/i
    matched = regex.match(text)
    matched[1] if matched
  end

  def orcid_works(orcid)
    works = []
    orcid_url = "#{ORCID_API}/#{orcid}/works"
    req = Typhoeus.get(orcid_url, headers: orcid_header)
    json = JSON.parse(req.body, symbolize_names: true)
    if json[:group] && json[:group].size > 0
      works = json[:group].map do |a|
        ids = a[:"work-summary"][0][:"external-ids"][:"external-id"] rescue []
        doi = ids.map{ |d| extract_doi(d[:"external-id-value"]) if d[:"external-id-type"] == "doi" }
                 .compact.first rescue nil
        title = a[:"work-summary"][0][:title][:title][:value] rescue nil
        { title: title, doi: doi }
      end
    end
    works
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
    if !@config[:orcid_keywords] || !@config[:orcid_keywords].is_a?(Array)
      raise ArgumentError, 'ORCID keywords to search on not in config.yml' 
    end

    keyword_parameter = URI::encode(@config[:orcid_keywords].map{ |k| "keyword:#{k}" }.join(" OR "))
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
    lucene_chars = {
      '+' => '\+',
      '-' => '\-',
      '&' => '\&',
      '|' => '\|',
      '!' => '\!',
      '(' => '\(',
      ')' => '\)',
      '{' => '\{',
      '}' => '\}',
      '[' => '\[',
      ']' => '\]',
      '^' => '\^',
      '"' => '\"',
      '~' => '\~',
      '*' => '\*',
      '?' => '\?',
      ':' => '\:'
    }
    clean_doi = URI::encode(doi.gsub(/[#{lucene_chars.keys.join('\\')}]/, lucene_chars))

    Enumerator.new do |yielder|
      start = 0
      loop do
        orcid_search_url = "#{ORCID_API}/search?q=doi-self:#{clean_doi}&start=#{start}&rows=50"
        req = Typhoeus.get(orcid_search_url, headers: orcid_header)
        results = JSON.parse(req.body, symbolize_names: true)[:result] rescue []
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
    country_name = IsoCountryCodes.find(o[:country]).name rescue nil
    doc["given_names"] = o[:given_names]
    doc["family_name"] = o[:family_name]
    doc["other_names"] = o[:other_names]
    doc["country"] = o[:country]
    doc["country_name"] = country_name
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

  def new_taxonomists
    @db.view('taxonomist/by_new_taxonomists')['rows']
       .map{|t| t["value"]}.compact
  end

  def all_taxonomists
    @db.view('taxonomist/by_updated_taxonomists')['rows']
       .map{|t| t["value"]}.compact
       .sort_alphabetical_by{|k| k["family_name"]}
  end

  def all_countries
    @db.view('taxonomist/by_country_code', :group_level => 1)['rows']
        .map{ |t| [t["key"],{ name: IsoCountryCodes.find(t["key"]).name, count: t["value"] }] }
        .to_h
  end

  def existing_orcids
    @db.all_docs["rows"]
       .map{|d| d["id"] if d["id"][0] != "_"}.compact
  end

  def output
    {
      couch_url: "#{@config[:public_server]}/#{@config[:database]}/",
      google_analytics: @config[:google_analytics],
      country_data: all_countries.to_json,
      num_taxonomists: all_taxonomists.count
    }
  end

end
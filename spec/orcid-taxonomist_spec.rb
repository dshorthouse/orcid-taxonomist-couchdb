describe "OrcidTaxonomist" do
  subject { OrcidTaxonomist }
  let(:ot) { subject.new({ config_file: CONFIG_FILE }) }

  describe ".new" do
    it "works" do
      expect(ot).to be_kind_of OrcidTaxonomist
    end
  end

  describe "String.is_doi?" do
    it "recognizes 10.1111/geb.12667 as a doi" do
      doi = "10.1111/geb.12667"
      expect(doi.is_doi?).to be true
    end
    it "recognizes 10.18195/issn.0312-3162.31(1).2016.027-040 as a doi" do
      doi = "10.18195/issn.0312-3162.31(1).2016.027-040"
      expect(doi.is_doi?).to be true
    end
    it "recognizes 10.1649/0010-065X(2006)60[275:ANGOMF]2.0.CO;2 as a doi" do
      doi = "10.1649/0010-065X(2006)60[275:ANGOMF]2.0.CO;2"
      expect(doi.is_doi?).to be true
    end
    it "recognizes 10.1111 as an invalid doi" do
      doi = "10.1111"
      expect(doi.is_doi?).to be false
    end
    it "recognizes 10.1111/ as an invalid doi" do
      doi = "10.1111/"
      expect(doi.is_doi?).to be false
    end
    it "recognizes 10.111/geb.12667 as a doi" do
      doi = "10.111/geb.12667"
      expect(doi.is_doi?).to be false
    end
  end

  describe "String.is_orcid?" do
    it "recognizes 0000-0000-0000-0000 as an ORCID" do
      orcid = "0000-0000-0000-0000"
      expect(orcid.is_orcid?).to be true
    end
    it "recognizes 0000-0000-0000-000X as an ORCID" do
      orcid = "0000-0000-0000-000X"
      expect(orcid.is_orcid?).to be true
    end
    it "recognizes 0000-0000-0000-0000X as an invalid ORCID" do
      orcid = "0000-0000-0000-0000X"
      expect(orcid.is_orcid?).to be false
    end
    it "recognizes 000-0000-0000-0000 as an invalid ORCID" do
      orcid = "000-0000-0000-0000"
      expect(orcid.is_orcid?).to be false
    end
    it "recognizes 0000-0000-0000 as an invalid ORCID" do
      orcid = "0000-0000-0000"
      expect(orcid.is_orcid?).to be false
    end
  end

  def read(file)
    File.read(File.join(__dir__, "files", file))
  end

end

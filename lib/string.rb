class String
  def is_doi?
    doi_pattern = /(10[.][0-9]{4,}(?:[.][0-9]+)*\/(?:(?![%"#? ])\S)+)/i
    doi_pattern.match?(self)
  end

  def is_orcid?
    orcid_pattern = /\d{4}-\d{4}-\d{4}-\d{3}[0-9X]/
    orcid_pattern.match?(self)
  end
end
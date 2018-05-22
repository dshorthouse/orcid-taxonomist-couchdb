ORCID Taxonomist
===============================================

[![DOI](https://zenodo.org/badge/DOI/10.5281/zenodo.1208546.svg)](https://doi.org/10.5281/zenodo.1208546)
[![Build Status](https://travis-ci.org/dshorthouse/orcid-taxonomist-couchdb.svg?branch=master)](https://travis-ci.org/dshorthouse/orcid-taxonomist-couchdb)

Ruby application that queries the ORCID API for user profiles containing keyword 'taxonomist', 'taxonomy', 'nomenclature', or 'systematics' then feeds the titles of their linked works to the Global Names Recognition and Discovery service to indicate the ORCID account holder's area of taxonomic expertise. Other data come from [ZooBank](http://zoobank.org/), thanks to [Rich Pyle](https://github.com/deepreef).

Requirements
------------
- Linux-based OS
- ruby 2.4.1
- CouchDB 2.1+

Set-Up
------

I recommend installation of [RVM](https://rvm.io/) and then install version 2.4.1 of ruby as follows:

`rvm install 2.4.1`

Clone the repository:

`git clone git@github.com:dshorthouse/orcid-taxonomist-couchdb.git`

Navigate into the cloned directory via the console and verify that ruby 2.4.1 is being used & the gemset called orcid-taxonomist was created.

```
cd orcid-taxonomist-couchdb
which ruby
rvm gemset name
rvm gemset dir
```

Adjust contents of config.yml.sample and rename it to config.yml. Install dependencies.

```
gem install bundler
bundle install
```

Initialize the CouchDB database and create the included design document with views:

`./bin/app.rb -i`

View all options for the command-line app:

`./bin/app.rb -h`

Create two CouchDB indices on family\_name and another on country\_name to permit sorting as follows:

```
{
   "index": {
      "fields": [
         "family_name"
      ]
   },
   "name": "family-index",
   "type": "json"
}
```

```
{
   "index": {
      "fields": [
         "country_name"
      ]
   },
   "name": "country-name-index",
   "type": "json"
}
```

License
-------
See included [LICENSE-en](LICENSE-en) and [LICENCE-fr](LICENCE-fr).

Disclaimer
----------
This project is in incubation status, is incomplete, and is unstable.

Contact
-------
David P. Shorthouse, <dshorthouse@nature.ca>
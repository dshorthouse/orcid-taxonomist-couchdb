$(function() {
  var couchdb_url = "http://127.0.0.1:5984/orcid_taxonomist/_design/taxonomist/_view/";

  var table = $('#taxonomists').DataTable({
    bSort: true,
    searching: true,
    processing: true,
    serverSide: true,
    order: [[1, "asc"]],
    pageLength: 100,
    ajax: {
      url: couchdb_url + "by_taxonomists_with_taxa/",
      dataSrc: "rows",
      data: function (d) {
        delete(d.columns);
        d.include_docs = true;
        d.limit = d.length;
        d.skip = d.start;
        if (d.search && d.search["value"] && d.search["value"] != "" ){
          //"Search" here send data using key parameter, which depends on which view is used
          d.key = '"' + d.search["value"] + '"';
          delete d.search["value"];
          delete d.search["regex"];
        }
      },
      dataFilter: function(data) {
        var data = JSON.parse(data);
        data['recordsTotal'] = data["total_rows"];
        data['recordsFiltered'] = data["total_rows"];
        return JSON.stringify(data);
      }
    },
    columns: [
      { data: "doc.given_names" },
      { data: "doc.family_name" },
      { data: "doc.other_names" },
      { data: "doc.country" },
      { data: "doc.taxa" },
      { data: "doc.orcid" }
    ],
    columnDefs: [
      { orderable: false, targets: [0,2,4,5] }
    ],
    rowCallback: function(row, data, index) {
      if (data.doc.other_names) {
        $('td:eq(2)', row).html(data.doc.other_names.join("; "));
      }
      if (data.doc.country) {
        $('td:eq(3)', row).html(countryData[data.doc.country].name);
      }
      if (data.doc.taxa) {
        $('td:eq(4)', row).html(data.doc.taxa.join(", "));
      }
      if (data.doc.orcid) {
        var orcid_html = '<a href="https://orcid.org/'+data.doc.orcid+'">';
        orcid_html += '<img alt="ORCID iD icon" class="id-icon" src="img/id-icon.svg" width="16" />';
        orcid_html += 'https://orcid.org/'+data.doc.orcid+'</a>';
        $('td:eq(5)', row).html(orcid_html);
      }
    }
  });
  table.on("preXhr.dt", function (e, settings, d) {
    if (d.order && d.order[0]) {
      if (d.order[0]["dir"] == "desc") {
        d.descending = true;
      }
      if (d.order[0]["column"] == 1) {
        settings.ajax.url = couchdb_url + "by_taxonomists_with_taxa/";
      }
      if (d.order[0]["column"] == 3) {
        settings.ajax.url = couchdb_url + "by_country_with_taxa/";
      }
    }
  });
  $('#map-modal').on('shown.bs.modal', function (e) {
    var map = $('#world-map');
    if (map.children().length === 0) {
        map.vectorMap({
          map: 'world_mill',
          backgroundColor: '#eee',
          series: {
            regions: [{
              values: Object.keys(countryData).reduce(function (result,item) {
                result[item] = countryData[item].count;
                return result; 
              }, {}),
              scale: ['#C8EEFF', '#0071A4'],
              normalizeFunction: 'polynomial'
            }]
          },
          onRegionTipShow: function(e, el, code) {
            count = 0
            if (countryData.hasOwnProperty(code)) {
              count = countryData[code].count;
            }
            el.html(el.html()+' ('+count+')');
          },
          onRegionClick: function(e, code) {
            if (countryData.hasOwnProperty(code)) {
              $('#taxonomists_filter').find('input').val(countryData[code].name);
              table.search(countryData[code].name).draw();
            }
            $('#map-modal').modal('toggle');
          }
        });
    }
  });
});
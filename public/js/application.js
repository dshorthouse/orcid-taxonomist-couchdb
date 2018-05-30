$(function() {

  var bookmarks = {};

  var table = $('#taxonomists').DataTable({
    bSort: true,
    searching: true,
    pagingType: "simple",
    processing: true,
    serverSide: true,
    order: [[1, "asc"]],
    pageLength: 25,
    ajax: {
      type: "POST",
      contentType: "application/json",
      dataType: "json",
      url: couch_url + "_find/",
      dataSrc: "docs",
      data: function(d) {
        d.fields = ["given_names", "family_name", "other_names", "country_name", "taxa", "orcid"];
        d.limit = d["length"];
        if (d.hasOwnProperty("order")) {
          var dir = d["order"][0]["dir"];
          if (d["order"][0]["column"] == 1) {
            d.sort = [{ "family_name" : dir}];
          } else if (d["order"][0]["column"] == 3) {
            d.sort = [{ "country_name" : dir}];
          }
        }
        var search = $.map(d.search["value"].replace(/[\.]/g, "").split(""), function(d) {
          return "[" + d.toUpperCase() + "|" + d.toLowerCase() + "]";
        }).join("");
        var or_clause = { "$or" : [
            { "family_name" : { "$regex" : "^" + search + "" } },
            { "given_names" : { "$regex" : "^" + search + "" } },
            { "other_names" : { "$elemMatch" : { "$regex" : "^" + search + "" } } },
            { "country_name" : { "$regex" : "^" + search + "" } },
            { "taxa" : { "$elemMatch" : { "$regex" : "" + search + "" } } }
          ]
        };
        d.selector = { 
          "status" : 1,
          "$and" : [
            { "family_name" : { "$ne" : null } },
            { "family_name" : { "$ne" : "" } }
          ]
        }
        if (search) { 
          $.extend(d.selector, or_clause);
        }
        delete(d["columns"]);
        delete(d["draw"]);
        delete(d["start"]);
        delete(d["length"]);
        delete(d["order"]);
        delete(d["search"]);
      },
      dataFilter: function(d) {
        var data = JSON.parse(d);
        data['recordsTotal'] = recordsTotal;
        data['recordsFiltered'] = recordsTotal;
        return JSON.stringify(data);
      }
    },
    columns: [
      { data: "given_names", "defaultContent": "" },
      { data: "family_name", "defaultContent": "" },
      { data: "other_names", "defaultContent": "" },
      { data: "country_name", "defaultContent": "" },
      { data: "taxa", "defaultContent": "" },
      { data: "orcid" }
    ],
    columnDefs: [
      { orderable: false, targets: [0,2,4,5] }
    ],
    rowCallback: function(row, data, index) {
      if (data.other_names) {
        $('td:eq(2)', row).html(data.other_names.join("; "));
      }
      if (data.taxa) {
        $('td:eq(4)', row).html(data.taxa.join(", "));
      }
      if (data.orcid) {
        var orcid_html = '<a href="https://orcid.org/'+data.orcid+'">';
        orcid_html += '<img alt="ORCID iD icon" class="id-icon" src="img/id-icon.svg" width="16" />';
        orcid_html += 'https://orcid.org/'+data.orcid+'</a>';
        $('td:eq(5)', row).html(orcid_html);
      }
    }
  });

  table.on("xhr.dt", function(e, settings, json, xhr) {
    bookmarks[table.page.info().page] = json.bookmark;
  });

  table.on("preXhr.dt", function(e, settings, json) {
    json["bookmark"] = bookmarks[table.page.info().page - 1];
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
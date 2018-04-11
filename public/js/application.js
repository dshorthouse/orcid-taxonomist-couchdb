$(function() {
  var table = $('#taxonomists').DataTable({
    order: [[1, "asc"]],
    pageLength: 100
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
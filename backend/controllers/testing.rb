class ArchivesSpaceService < Sinatra::Base
  if AppConfig.has_key?(:yale_marc_export_enable_test_endpoint) && AppConfig[:yale_marc_export_enable_test_endpoint]
    Endpoint.get('/run-marc-export')
      .description("For testing")
      .permissions([])
      .returns([200, ""]) \
    do
      AccessionMarcExporter.run!
      json_response({"toot" => "toot"})
    end
  end
end

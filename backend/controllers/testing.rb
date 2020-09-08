class ArchivesSpaceService < Sinatra::Base

  # FIXME remove when done
  Endpoint.get('/run-marc-export')
    .description("For testing")
    .permissions([])
    .returns([200, ""]) \
  do
    AccessionMarcExporter.run!
    json_response({"toot" => "toot"})
  end

end

if AppConfig.has_key?(:yale_accession_marc_export_schedule)
  ArchivesSpaceService.settings.scheduler.cron(AppConfig[:yale_accession_marc_export_schedule],
                                               :tags => 'yale_accession_marc_export') do
    AccessionMarcExporter.run!
  end
end

if AppConfig[:yale_accession_marc_export_target].to_s == 's3'
  Log.info("AccessionMarcExporter: Checking AWS S3 connection...")
  begin
    AWSUploader.new.test_connection
  rescue
    Log.exception($!)
    raise $!
  end
  Log.info("AccessionMarcExporter: OK!")
end

if AppConfig[:yale_accession_marc_export_target].to_s == 'sftp'
  Log.info("AccessionMarcExporter: Checking SFTP connection...")
  begin
    SFTPUploader.new.test_connection
  rescue
    Log.exception($!)
    raise $!
  end
  Log.info("AccessionMarcExporter: OK!")
end

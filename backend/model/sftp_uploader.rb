require 'net/sftp'

class SFTPUploader
  def self.upload!(filename, local_file)
    Net::SFTP.start(AppConfig[:yale_accession_marc_export_sftp_host],
                    AppConfig[:yale_accession_marc_export_sftp_username],
                    :password => AppConfig[:yale_accession_marc_export_sftp_password]) do |sftp|
      target_path = File.join(AppConfig[:yale_accession_marc_export_sftp_target_directory], filename)
      sftp.upload!(local_file.path, target_path)
    end
  end
end
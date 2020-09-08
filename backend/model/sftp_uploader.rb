require File.join(File.dirname(__FILE__), '..', 'lib', 'jzlib-1.1.3.jar')
require File.join(File.dirname(__FILE__), '..', 'lib', 'sshj-0.30.0.jar')
require File.join(File.dirname(__FILE__), '..', 'lib', 'asn-one-0.4.0.jar')
require File.join(File.dirname(__FILE__), '..', 'lib', 'bcpkix-jdk15on-1.66.jar')
require File.join(File.dirname(__FILE__), '..', 'lib', 'slf4j-api-1.7.7.jar')
require File.join(File.dirname(__FILE__), '..', 'lib', 'eddsa-0.3.0.jar')
require File.join(File.dirname(__FILE__), '..', 'lib', 'bcprov-jdk15on-1.66.jar')

class SFTPUploader

  def initialize
    @ssh_client = Java::net.schmizz.sshj.SSHClient.new
    @ssh_client.addHostKeyVerifier(Java::net.schmizz.sshj.transport.verification.PromiscuousVerifier.new)
    @ssh_client.connect(AppConfig[:yale_accession_marc_export_sftp_host], AppConfig[:yale_accession_marc_export_sftp_port])
    @ssh_client.authPassword(AppConfig[:yale_accession_marc_export_sftp_username], AppConfig[:yale_accession_marc_export_sftp_password])

    @sftp_client = @ssh_client.newSFTPClient
  end

  def upload!(filename, file_path)
    target_path = File.join(AppConfig[:yale_accession_marc_export_sftp_target_directory], filename)
    @sftp_client.put(file_path, target_path)
  end

  def test_connection
    @sftp_client.ls(AppConfig[:yale_accession_marc_export_sftp_target_directory]) || raise("Unable to connect to SFTP and ls target directory")
  end

end
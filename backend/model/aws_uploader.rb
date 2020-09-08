require 'aws-sdk-s3'

class AWSUploader

  def initialize
    @client = Aws::S3::Client.new(AppConfig[:yale_accession_marc_export_s3_client_opts])
    @resource = Aws::S3::Resource.new(client: @client)
    @bucket = @resource.bucket(AppConfig[:yale_accession_marc_export_s3_bucket])

    unless @bucket.exists?
      @bucket = @resource.create_bucket({
                                         :bucket => AppConfig[:yale_accession_marc_export_s3_bucket],
                                       })
    end
  end

  def upload!(filename, file_path)
    obj = @bucket.object(filename)
    obj.upload_file(file_path)
  end

  def test_connection
    @bucket.exists? || raise("Unable to connect to AWS S3 and create bucket")
  end

end
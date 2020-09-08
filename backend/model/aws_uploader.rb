require 'aws-sdk-s3'

class AWSUploader

  def self.upload!(filename, file_path)
    client = Aws::S3::Client.new(AppConfig[:yale_accession_marc_export_s3_client_opts])
    resource = Aws::S3::Resource.new(client: client)
    bucket = resource.bucket(AppConfig[:yale_accession_marc_export_s3_bucket])

    unless bucket.exists?
      bucket = resource.create_bucket({
                                         :bucket => AppConfig[:yale_accession_marc_export_s3_bucket]
                                       })
    end

    obj = bucket.object(filename)
    obj.upload_file(file_path)
  end
end
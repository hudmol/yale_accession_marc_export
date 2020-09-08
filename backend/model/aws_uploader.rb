require 'aws-sdk-s3'

class AWSUploader


  AppConfig[:yale_accession_marc_export_s3_client_opts] = {
    :access_key_id => 'you_access_key_id',
    :secret_access_key => 'your_secret_access_key',
    :region => 'your_region',
  }


  def self.upload!(filename, local_file)
    client = Aws::S3::Client.new(AppConfig[:yale_accession_marc_export_s3_client_opts])
    resource = Aws::S3::Resource.new(client: client)

    bucket = resource.bucket(AppConfig[:yale_accession_marc_export_s3_bucket])

    unless bucket.exists?
      bucket = resource.buckets.create(AppConfig[:yale_accession_marc_export_s3_bucket])
    end

    obj = bucket.object(filename)
    obj.upload_file(local_file)
  end
end
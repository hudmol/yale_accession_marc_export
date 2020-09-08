# yale_accession_marc_export

## WIP Config

```
# AppConfig[:yale_marc_export_schedule] = '15 0 * * *' # 00:15 daily
# AppConfig[:yale_accession_marc_export_schedule] = '*/1 * * * *' # every minute
AppConfig[:yale_accession_marc_export_target] = 'local'
AppConfig[:yale_accession_marc_export_path] = '/path/to/marc_exports'
```

Run export round (testing only):

```
scripts/curl_as admin admin http://localhost:4567/run-marc-export
```

Test S3:

```
docker run --env initialBuckets=MARCuploads --env  validKmsKeys=arn:aws:kms:us-east-1:47110815:key/c51fdeea-f623-4a2b-90b5-15d72963cf9d,arn:aws:kms:us-east-1:47110815:key/c4353c4c-3318-460a-bdcc-b0a57bd8d9d8 -p 9090:9090 -p 9191:9191 -t adobe/s3mock
```

```
AppConfig[:yale_accession_marc_export_target] = 's3'
AppConfig[:yale_accession_marc_export_s3_client_opts] = {
  :endpoint => 'http://localhost:9090',
  :access_key_id => '47110815',
  :secret_access_key => 'c51fdeea-f623-4a2b-90b5-15d72963cf9d',
  :region => 'us-east-1',
}
AppConfig[:yale_accession_marc_export_s3_bucket] = 'MARCuploads'
```

Test SFTP:

```
docker run \
    -v /tmp/upload:/home/foo/upload \
    -p 2222:22 -d atmoz/sftp \
    foo:pass:1001
```

```
AppConfig[:yale_accession_marc_export_target] = 'sftp'
AppConfig[:yale_accession_marc_export_sftp_host] = 'localhost'
AppConfig[:yale_accession_marc_export_sftp_port] = 2222
AppConfig[:yale_accession_marc_export_sftp_username] = 'foo'
AppConfig[:yale_accession_marc_export_sftp_password] = 'pass'
AppConfig[:yale_accession_marc_export_sftp_target_directory] = '/upload'
```
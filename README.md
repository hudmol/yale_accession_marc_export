# Accession MARC Export Plugin

This is an ArchivesSpace plugin that exports accession payment data as binary MARC for ingest into Yale's Voyager system.

This plugin was developed by Hudson Molonglo for Yale University.

## Getting Started

Download the latest release from the Releases tab in Github:

  https://github.com/hudmol/yale_accession_marc_export/releases

Unzip the release and move it to:

    /path/to/archivesspace/plugins

Unzip it:

    $ cd /path/to/archivesspace/plugins
    $ unzip yale_accession_marc_export-vX.X.zip

Enable the plugin by editing the file in `config/config.rb`:

    AppConfig[:plugins] = ['some_plugin', 'yale_accession_marc_export']

(Make sure you uncomment this line (i.e., remove the leading '#' if present))

Install Ruby gem dependencies by initializing the plugin:

    $ cd /path/to/archivesspace
    $ ./scripts/initialize-plugin.sh yale_accession_marc_export

See also:

  https://archivesspace.github.io/archivesspace/user/archivesspace-plug-ins/

## Dependencies

This plugin requires the payments_module plugin (v1.3 or higher) be installed and running. Find this plugin here: https://github.com/hudmol/payments_module.

## Configuration

```
AppConfig[:yale_accession_marc_export_schedule] = '15 0 * * *' # 00:15 daily
AppConfig[:yale_accession_marc_export_location_code] = 'beints'
```

Note: leave `AppConfig[:yale_accession_marc_export_schedule]` blank or set to `nil` to disable the export task.

### Export to local file system
```
AppConfig[:yale_accession_marc_export_target] = 'local'
AppConfig[:yale_accession_marc_export_path] = '/path/to/marc_exports'
```

### Export to S3
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
For supported `client_opts` see https://docs.aws.amazon.com/sdk-for-ruby/v2/api/Aws/S3/Client.html#initialize-instance_method.

### Export to SFTP
```
AppConfig[:yale_accession_marc_export_target] = 'sftp'
AppConfig[:yale_accession_marc_export_sftp_host] = 'localhost'
AppConfig[:yale_accession_marc_export_sftp_port] = 2222
AppConfig[:yale_accession_marc_export_sftp_username] = 'foo'
AppConfig[:yale_accession_marc_export_sftp_password] = 'pass'
AppConfig[:yale_accession_marc_export_sftp_target_directory] = '/upload'
```

If you prefer to use an SSH key for authentication, you can specify
`AppConfig[:yale_accession_marc_export_sftp_private_key_path]` instead
of `AppConfig[:yale_accession_marc_export_sftp_password]`:

```
AppConfig[:yale_accession_marc_export_sftp_private_key_path] = '/path/to/id_rsa_file'
```

The SSH key should be unencrypted (i.e. should be passwordless).

### Email Notifications

By default the plugin will provide a running commentary of the export to the ArchivesSpace log.  If you would like to be emailed upon success or failure of the export you may configure these logs to be sent to an email of your choice.  For example:

```
# disabled
# - leave blank
# AppConfig[:yale_accession_marc_export_email_delivery_method]

# sendmail
AppConfig[:yale_accession_marc_export_email_delivery_method] = :sendmail
AppConfig[:yale_accession_marc_export_email_delivery_method_settings] = {
    :sendmail_settings => {
        ...
    }
}
AppConfig[:yale_accession_marc_export_email_from_address] = 'your@email.com'
AppConfig[:yale_accession_marc_export_email_to_address] = 'your@email.com'

# SMTP
AppConfig[:yale_accession_marc_export_email_delivery_method] = :smtp
AppConfig[:yale_accession_marc_export_email_delivery_method_settings] = {
    :smtp_settings => {
        :address => 'your.smtp.com',
        :port => 25,
        :user_name => 'smtpusername',
        :password => 'pw',
        ...
    }
}
AppConfig[:yale_accession_marc_export_email_from_address] = 'your@email.com'
AppConfig[:yale_accession_marc_export_email_to_address] = 'your@email.com'
```

For full configuration settings, please see https://guides.rubyonrails.org/action_mailer_basics.html#action-mailer-configuration.

# Development/testing notes

Run export round (development only):

```
AppConfig[:yale_accession_marc_export_enable_test_endpoint] = true
```

```
scripts/curl_as admin admin http://localhost:4567/run-marc-export
```

Testing S3:

```
docker run --env initialBuckets=MARCuploads --env  validKmsKeys=arn:aws:kms:us-east-1:47110815:key/c51fdeea-f623-4a2b-90b5-15d72963cf9d,arn:aws:kms:us-east-1:47110815:key/c4353c4c-3318-460a-bdcc-b0a57bd8d9d8 -p 9090:9090 -p 9191:9191 -t adobe/s3mock
```

Testing SFTP:

```
docker run \
    -v /tmp/upload:/home/foo/upload \
    -p 2222:22 -d atmoz/sftp \
    foo:pass:1001
```

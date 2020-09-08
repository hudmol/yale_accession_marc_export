# yale_accession_marc_export

## WIP Config

```
# AppConfig[:yale_marc_export_schedule] = '15 0 * * *' # 00:15 daily
# AppConfig[:yale_accession_marc_export_schedule] = '*/1 * * * *' # every minute
AppConfig[:yale_accession_marc_export_target] = 'local'
AppConfig[:yale_accession_marc_export_path] = '/path/to/marc_exports'
```

For testing:

```
scripts/curl_as admin admin http://localhost:4567/run-marc-export
```
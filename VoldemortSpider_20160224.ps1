Add-Type -Assembly System.ServiceModel.Web,System.Runtime.Serialization;

$errorBody = '';
$stagingDBServer = "hdc405prdbsv015";
$stagingDB = "FalconStaging";

### Convert JSON Data to XML ###
Function ConvertWeb-JsonToXML($url)
{
  $web = [System.Net.WebRequest]::Create($url);
  $web.ContentType = 'application/json';

  ### Set proxy settings                                   ###
  $proxy = New-Object System.Net.WebProxy("proxy.hdc.mdsol.com:3128")
  $proxy.useDefaultCredentials = $true
  $web.proxy = $proxy

  $res = $web.GetResponse();
  $strm = $res.GetResponseStream();
  $data = New-Object System.IO.StreamReader $strm;
  $json = $data.ReadToEnd();
  $strm.Close();
  $res.Close();

  $bytes = [byte[]][char[]]$json;
  $quotas = [System.Xml.XmlDictionaryReaderQuotas]::Max;
  $jsonReader = [System.Runtime.Serialization.Json.JsonReaderWriterFactory]::CreateJsonReader($bytes, $quotas);
  try
  {
    $xml = New-Object System.Xml.XmlDocument;
    $xml.Load($jsonReader);
  }
  finally
  {
    $jsonReader.Close();
  }
  return $xml;
}

$startDT = Get-Date -Format s;

$rdsDetails = ConvertWeb-JsonToXML 'https://voldemort.imedidata.com/api/v1/aws_rds_details/';
$instanceDetails = ConvertWeb-JsonToXML 'https://voldemort.imedidata.com/api/v1/aws_instance_details/';

### Clear Staging Tables ###
sqlcmd -E -d $stagingDB -S $stagingDBServer -Q "exec usp_ps_InitAWSTables";

### Get AWS RDS Data ###
$count = 0; $cmd = '';
Select-Xml "//root/item" $rdsDetails | % {
  $rdsItems = @{};
  $_.Node.ChildNodes | % { if ($_.'#text' -eq $null) { $rdsItems.$($_.Name) = ""; } else { $rdsItems.$($_.Name) = $_.'#text'; } }
  $cmd += "exec usp_ps_SetAWSRDS @AccountName = '$($rdsItems.account_name)', @AvailabilityZone = '$($rdsItems.availabilityzone)', @BackupRetentionPeriod = '$($rdsItems.backup_retention_period)', @Company = '$($rdsItems.company)', @DataCollectionDT = '$($rdsItems.data_collection_date)', @DBAddress = '$($rdsItems.dbaddress)', @DBCreatedDT = '$($rdsItems.dbcreatetime)', @DBEngine = '$($rdsItems.dbengine)', @DBInstanceID = '$($rdsItems.dbinstanceid)', @DBInstanceState = '$($rdsItems.dbinstancestate)', @DBInstanceType = '$($rdsItems.DBInstanceType)', @DBName = '$($rdsItems.dbname)', @DBPort = '$($rdsItems.dbport)', @DBStorage = '$($rdsItems.dbstorage)', @DynURL_ID = '$($rdsItems.dynurl_id)', @EngineVersion = '$($rdsItems.engine_version)', @Environment = '$($rdsItems.environment)', @LatestRestoreDT = '$($rdsItems.latestrestoretime)', @MultiAZ = '$($rdsItems.multi_az)', @Product = '$($rdsItems.product)'; ";
  if ($count -ge 20) { sqlcmd -E -d $stagingDB -S $stagingDBServer -Q $cmd; $cmd = ''; $count = 0; }
  else { $count++; } 
}
if ($cmd.Length -gt 0) { sqlcmd -E -d $stagingDB -S $stagingDBServer -Q $cmd; }

### Get AWS Instance Data ###
$count = 0; $cmd = '';
Select-Xml "//root/item" $instanceDetails | % {
  $instItems = @{};
  $_.Node.ChildNodes | % {
    if ($_.'#text' -eq $null) { $instItems.$($_.Name) = ""; } else { $instItems.$($_.Name) = $_.'#text'; }
  }
  if ($instItems.tag -ne $null) { $instItems.tag = $instItems.tag.Replace("'","''").Trim("`t`n`r"); } 
  if ($instItems.tag_company -ne $null) { $instItems.tag_company = $instItems.tag_company.Replace("'","''").Trim("`t`n`r"); } 
  if ($instItems.tag_name -ne $null) { $instItems.tag_name = $instItems.tag_name.Replace("'","''").Trim("`t`n`r"); } 
  if ($instItems.TagProduct -ne $null) { $instItems.TagProduct = $instItems.TagProduct.Replace("'","''").Trim("`t`n`r"); } 
  if ($instItems.tag_type -ne $null) { $instItems.tag_type = $instItems.tag_type.Replace("'","''").Trim("`t`n`r"); } 
  $cmd += "exec usp_ps_SetAWSInstance @AccountName = '$($instItems.account_name)', @AvailabilityZone = '$($instItems.availability_zone)', @DataCollectionDT = '$($instItems.data_collection_date)', @DNSName = '$($instItems.dnsname)', @Environment = '$($instItems.environment)', @ImageID = '$($instItems.imageid)', @InstanceCreatedDT = '$($instItems.instance_created)', @InstanceID = '$($instItems.instance_id)', @InstanceOwner = '$($instItems.instance_owner)', @InstanceState = '$($instItems.instance_state)', @InstanceType = '$($instItems.instance_type)', @IPAddress = '$($instItems.ipaddress)', @Platform = '$($instItems.platform)', @PlatformVersion = '$($instItems.platform_version)', @PrivateDNS = '$($instItems.privatedns)', @PrivateIPAddress = '$($instItems.privateidaddress)', @Region = '$($instItems.region)', @Tag = '$($instItems.tag)', @TagCompany = '$($instItems.tag_company)', @TagName = '$($instItems.tag_name)', @TagProduct = '$($instItems.TagProduct)', @TagType = '$($instItems.tag_type)', @VPSID = '$($instItems.vpsid)'; ";
  if ($count -ge 20) { sqlcmd -E -d $stagingDB -S $stagingDBServer -Q $cmd; $cmd = ''; $count = 0; }
  else { $count++; } 
}
if ($cmd.Length -gt 0) { sqlcmd -E -d $stagingDB -S $stagingDBServer -Q $cmd; }

$finishDT = Get-Date -Format s;

#### Record Script Performance ###
sqlcmd -E -d $stagingDB -S $stagingDBServer -Q "exec usp_ps_SetScriptPerformance @ScriptName='VoldemortSpider', @startDT='$startDT', @finishDT='$finishDT';";

### Evaluate Script Execution And Notify If Unusual ###
$result = sqlcmd -E -d $stagingDB -S $stagingDBServer -Q "EXEC usp_ps_GetScriptPerformance 'VoldemortSpider'";
if ($result.Failed -gt 0) {
  $to = sqlcmd -E -d $stagingDB -S $stagingDBServer -Q "EXEC usp_ps_GetScriptConfig 'ScriptNotificationDL'";
  $from = sqlcmd -E -d $stagingDB -S $stagingDBServer -Q "EXEC usp_ps_GetScriptConfig 'ScriptEmailAddress'";
  $smtp = sqlcmd -E -d $stagingDB -S $stagingDBServer -Q "EXEC usp_ps_GetScriptConfig 'ScriptSMTP'";
  Send-MailMessage -From $from.Setting -To $to.Setting.Split(';') -SmtpServer $smtp.Setting -Subject "VoldemortSpider - Possible Falcon spider issue" -Body "The VoldemortSpider runtime duration was outside of it's normal duration."
}
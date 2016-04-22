var http = require('http');
var port = process.env.port || 1337;
var os = require('os');
const fs = require('fs');
var searchDir = 'C:/temp';

var files = fs.readdirSync(searchDir);

function getDateTime() {
	
	var date = new Date();
	
	var hour = date.getHours();
	hour = (hour < 10 ? "0" : "") + hour;
	
	var min = date.getMinutes();
	min = (min < 10 ? "0" : "") + min;
	
	var sec = date.getSeconds();
	sec = (sec < 10 ? "0" : "") + sec;
	
	var year = date.getFullYear();
	
	var month = date.getMonth() + 1;
	month = (month < 10 ? "0" : "") + month;
	
	var day = date.getDate();
	day = (day < 10 ? "0" : "") + day;
	
	return year + ":" + month + ":" + day + ":" + hour + ":" + min + ":" + sec;

}

http.createServer(function (req, res) {
	res.writeHead(200, { 'Content-Type': 'application/json' });
	var resTxt = 'Info about ' + os.hostname() + '\n';
	resTxt += 'Platform ' + os.platform() + '\n';
	resTxt += 'OS Release ' + os.release() + '\n';
	resTxt += 'Contents of ' + searchDir + ' directory:\n';
	var systemInfo = {'Hostname': os.hostname(), 'Platform': os.platform(), 'OSRelease' : os.release(),'Search Directory': searchDir };
	for ( i in files) {
		resTxt += '\t' + files[i] + '\n';
	};
	resTxt += 'Time is ' + getDateTime() + '\n';
	resTxt += JSON.stringify(systemInfo,null,3);

	
	
    res.end(resTxt);
}).listen(port);



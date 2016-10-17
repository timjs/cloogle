function makeUnifier(ufr) {
	var from_left = ufr[0];
	var from_right = ufr[1];
	var s = '';
	for (i in from_right) {
		s += '<tt>' + from_right[i][0] + '</tt> &rarr; <tt>' + from_right[i][1] + '</tt>; ';
	}
	for (i in from_left) {
		s += '<tt>' + from_left[i][1] + '</tt> &larr; <tt>' + from_left[i][0] + '</tt>; ';
	}
	return s.substring(0, s.length - 2);
}

function highlightCallback(span, cls, str) {
	if (cls == 'type') {
		return '<a class="hidden" title="Search type ' + str + '" href="#' +
			encodeURIComponent('type ' + str) + '">' +
			span + '</a>';
	} else if (cls == 'classname') {
		return '<a class="hidden" title="Search class ' + str + '" href="#' +
			encodeURIComponent('class ' + str) + '">' +
			span + '</a>';
	} else if (cls == 'generic') {
		return '<a class="hidden" title="Search generic ' + str + '" href="#' +
			encodeURIComponent(str) + '">' +
			span + '</a>';
	} else if (cls == 'funcname funcname-onlyused' || cls == 'constructor') {
		return '<a class="hidden" title="Search ' + str + '" href="#' +
			encodeURIComponent(str) + '">' +
			span + '</a>';
	} else {
		return span;
	}
}

var derivationsIdCounter = 0;
var old_str = null;
var old_libs = null;

function getResults(str, libs, page) {
	if (str == null)  str  = old_str;
	if (libs == null) libs = old_libs;

	old_str  = str;
	old_libs = libs;

	var url = 'api.php' +
		'?str='  + encodeURIComponent(str) +
		(libs.length > 0 ? ('&lib=' + encodeURIComponent(libs[0])) : '') +
		(libs.length > 0 ? ('&libs_builtin=' + encodeURIComponent(libs[1])) : '') +
		'&page=' + page;
	var xmlHttp = new XMLHttpRequest();

	var elem = document.getElementById('page-' + page);

	elem.innerHTML += '<p id="loading">Processing...</p>';
	var more = document.getElementById('more');
	if (more !== null) {
		more.remove();
	}

	var makeTable = function (d) {
		var html = '<table>';
		for (i in d) {
			if (d[i].length == 1) {
				html += '<tr><td colspan="2">' + d[i][0] + '</td></tr>';
			} else if (d[i].length == 2) {
				html += '<tr><th>' + d[i][0] + ': </th><td class="wide">' +
					d[i][1] + '</td></tr>';
			}
		}
		html += '</table>';
		return html;
	}

	var makeInstanceTable = function (id, list) {
		var instances = '<a href="javascript:toggle(\'' + id + '\')">show / hide</a>';
		instances += '<table id="' + id + '" style="display:none;">';
		var makeInstanceUrl = function (loc) {
			var dclUrl =
				'src/view.php?lib=' + encodeURIComponent(loc[0]) +
				'&mod=' + encodeURIComponent(loc[1]) +
				'&hl';
			var iclUrl = dclUrl + '&icl';
			if (loc[2].length > 1) {
				dclUrl += '&line=' + loc[2][1] + '#line-' + loc[2][1];
			}
			return '<a target="_blank" ' +
				'href="' + dclUrl + '" ' +
				'title="' + loc[0] + '">' + loc[1] + '</a> (' +
				'<a target="_blank" href="' + iclUrl + '">icl</a>)';
		}
		for (var i in list) {
			instances += '<tr><th><code>' +
				highlightType(list[i][0],
						highlightCallback) +
				'</code></th>';
			var locs = '';
			for (var j in list[i][1]) {
				var loc = list[i][1][j];
				if (locs != '') {
					locs += ', ';
				}
				locs += makeInstanceUrl(loc);
			}
			instances += '<td>in: ' + locs + '</td></tr>';
		}
		instances += '</table>';
		return instances;
	}

	var makeResultHTML = function (result) {
		var kind = result[0];
		var basic = result[1][0];
		var specific = result[1][1];

		var dclUrl =
			'src/view.php?lib=' + encodeURIComponent(basic['library']) +
			'&mod=' + encodeURIComponent(basic['modul']) +
			'&hl';
		var iclUrl = dclUrl + '&icl';
		if ('dcl_line' in basic) {
			dclUrl += '&line=' + basic['dcl_line'] + '#line-' + basic['dcl_line'];
		}

		var basicData = [
			['Library',  basic['library']],
			['Filename', '<a href="' + dclUrl + '" target="_blank">' +
				basic['filename'] + ('dcl_line' in basic ? ':' + basic['dcl_line'] : '') +
				'</a> (<a href="' + iclUrl + '" target="_blank">icl</a>)'],
			['Module',   basic['modul']],
			['Distance', basic['distance']]
		];

		if ('builtin' in basic && basic['builtin']) {
			basicData.splice(0,3);
			basicData.push(['Builtin', 'yes (actual implementation may differ)']);
		}

		switch (kind) {
			case 'FunctionResult':
				var specificData = [];
				specificData.push(
					('cls' in specific ?
						[ 'Class', '<code>' +
						  highlightClassDef(specific['cls']['cls_name'] +
							  ' ' + specific['cls']['cls_vars'].join(' '),
							  highlightCallback, 'className') + '</code>'] :
						[]),
					('unifier' in specific &&
						(specific['unifier'][0].length > 0 ||
						 specific['unifier'][1].length > 0) ?
						['Unifier', makeUnifier(specific['unifier'])] :
						[])
				);
				if ('generic_derivations' in specific) {
					var derivationsId = 'derivations-' + (derivationsIdCounter++);
					var derivations = makeInstanceTable(derivationsId,
							specific['generic_derivations']);
					specificData.push(['Derivations', derivations]);
				}
				var hl_entry = 'start';
				if ('constructor_of' in specific) {
					specificData.push([
						'This function is a type constructor of <code>' +
						highlightFunction(':: ' + specific['constructor_of'],
							highlightCallback) + '</code>.'
					]);
					hl_entry = 'startConstructor';
				} else if ('recordfield_of' in specific) {
					specificData.push([
						'This is a record field of <code>' +
						highlightFunction(':: ' + specific['recordfield_of'],
							highlightCallback) + '</code>.'
					]);
					hl_entry = 'startRecordField';
				}
				return '<hr/>' +
					makeTable(basicData.concat(specificData)) +
					'<code>' +
					highlightFunction(specific['func'], highlightCallback, hl_entry) +
					'</code>';
				break;
			case 'TypeResult':
				return '<hr/>' +
					makeTable(basicData) +
					'<pre>' +
					highlightTypeDef(specific['type'], highlightCallback) +
					'</pre>';
				break;
			case 'ClassResult':
				var instancesId = 'instances-' + specific['class_name'];
				var instances = makeInstanceTable(instancesId,
						specific['class_instances']);
				var specificData = [['Instances', instances]];
				var html = '<hr/>' +
					makeTable(basicData.concat(specificData)) + '<pre>' +
					highlightClassDef(
							'class ' + specific['class_heading'] +
							(specific['class_funs'].length > 0 ? ' where' : ''),
							highlightCallback) +
					'<br/>';
				for (var i in specific['class_funs']) {
					html += '<br/>    ' +
						highlightFunction(specific['class_funs'][i],
								highlightCallback);
				}
				html += '</pre>';
				return html;
				break;
			case 'MacroResult':
				return '<hr/>' +
					makeTable(basicData) +
					'<pre>' +
					highlightMacro(specific['macro_representation'], highlightCallback) +
					'</pre>';
				break;
			default:
				return '';
		}
	}

	var makeSuggestions = function (suggs) {
		var str = '<hr/><div id="suggestions"><b>Did you mean...</b><table>';
		for (i in suggs) {
			var sug = suggs[i][0];
			var sugstr = []
			if ('name' in sug) {
				sugstr.push(sug.name);
			}
			if ('unify' in sug) {
				sugstr.push(':: ' + sug.unify);
			}
			sugstr = sugstr.join(' ');
			str += '<tr><td><a class="hidden" href="#' + encodeURIComponent(sugstr) + '"><code>' +
				highlightFunction(sugstr) + '</code></a></td><td>' +
				suggs[i][1] + ' results</td></tr>';
		}
		str += '</table></div>';
		return str;
	}

	xmlHttp.onreadystatechange = function () {
		if(xmlHttp.readyState == 4 && xmlHttp.status == 200){
			document.getElementById('loading').remove();
			var responsedata = JSON.parse(xmlHttp.responseText);
			if(responsedata['return'] === 0){
				for(var i = 0; i<responsedata['data'].length; i++){
					var c = responsedata['data'][i];
					elem.innerHTML += makeResultHTML(c);
				}

				var par = elem.parentNode
				if (responsedata['more_available'] != 0) {
					par.innerHTML += '<div id="page-' + (page+1) + '">' +
						'<p id="more"><a href="javascript:getResults(null,null,' + (page+1) +
						')">' + responsedata['more_available'] + ' more...</a></p>' +
						'</div>';
				}

				if ('suggestions' in responsedata &&
						responsedata['suggestions'].length > 0) {
					par.innerHTML =
						makeSuggestions(responsedata['suggestions'])
						+ par.innerHTML;
				}
			} else {
				elem.innerHTML =
					'<p>Return code: ' + responsedata['return'] + '</p>' +
					'<p>Message: ' + responsedata['msg'] + '</p>';
			}
		}
	};
	xmlHttp.open('GET', url, true); // true for asynchronous
	xmlHttp.send(null);
	if (document.location.hash.substring(1) != encodeURIComponent(str)) {
		refresh_on_hash = false;
		document.location.hash = "#" + encodeURIComponent(str);
	}
}

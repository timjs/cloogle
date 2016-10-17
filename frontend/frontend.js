var form_str = document.getElementById('search_str');
var form_libs = document.getElementById('search_libs');
var sform = document.getElementById('search_form');
var sresults = document.getElementById('search_results');
var advanced_checkbox = document.getElementById('search_advanced');
var refresh_on_hash = true;

function toggle(name) {
	var e = document.getElementById(name);
	e.style.display = e.style.display == 'block' ? 'none' : 'block';
}

function getLibs() {
	if (!advanced_checkbox.checked)
		return [];

	var builtin = false;
	var libs = [];
	for (var i = 0; i < form_libs.length; i++) {
		if (form_libs[i].selected) {
			if (form_libs[i].value == '__builtin')
				builtin = true;
			else
				libs.push(form_libs[i].value);
		}
	}

	return [libs, builtin];
}

function formsubmit() {
	var q = form_str.value;
	if (q === '') {
		sresults.innerHTML = 'Can\'t search for the empty string';
	} else {
		sresults.innerHTML = '';

		if (q.indexOf('::') == -1 && q.indexOf('->') != -1) {
			var sug = ':: ' + q.replace('->', ' -> ');
			sresults.innerHTML = '<p>' +
				'Searching for <code>' + highlightFunction(q) + '</code>. ' +
				'Did you mean to search for ' +
				'<a class="hidden" href="#' + sug + '"><code>' +
				highlightFunction(sug) + '</code></a>?</p>';
		}

		var libs = getLibs();
		sresults.innerHTML += '<div id="page-0"></div>';
		getResults(q, libs, 0);
	}
	return false;
};

advanced_checkbox.onchange = function () {
	toggle('advanced');
}

window.onhashchange = function () {
	if (!refresh_on_hash) {
		refresh_on_hash = true;
	} else {
		var str = decodeURIComponent(document.location.hash);
		form_str.value = str.substring(1);
		formsubmit();
	}
}

window.onload = function() {
	sform.onsubmit = formsubmit;
	var str = decodeURIComponent(document.location.hash);
	if(str !== ''){
		str = str.substring(1);
		form_str.value = decodeURIComponent(str);
		formsubmit();
	}

	if (advanced_checkbox.checked)
		advanced_checkbox.onchange();

	document.getElementById('search_str').focus();

	var caretOffset = 0;
	
	var updateCaret = function() {
		var search = form_str;
		var caret = document.getElementById('caret');
		var caretOffset = search.selectionStart;
		if (search.selectionStart != search.selectionEnd) {
			caret.style.display = 'none';
		} else {
			caret.style.marginLeft = caretOffset * 7 + 'px';
			caret.style.display = 'inline';
		}
	}
	
	form_str.onfocus = updateCaret;
	form_str.onclick = updateCaret;
	
	form_str.onkeypress = function() {
		var caret = '<span id="caret"></span>';
		this.style.width = Math.max(240, this.value.length * 7 + 7) + 'px';
		document.getElementById('search_str_highlight').innerHTML =
			caret + highlightFunction(this.value);
		updateCaret();
	}
	form_str.onkeyup = form_str.onkeypress;
	form_str.onchange = form_str.onkeypress;
	form_str.onkeypress();
	
	form_str.onblur = function() {
		document.getElementById('caret').style.display = 'none';
	}
	form_str.onfocus = function() {
		document.getElementById('caret').style.display = 'inline';
	}
}

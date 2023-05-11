;(function () {
	'use strict';

	$(document).ready(function(){
		const cte = window.convoTree.launch({
			ids: [1,2,3],
			div: $('.put-things-here'),
			name: 'perltest',
			api_url: 'https://perltest.com/data/',
		});
	});
}());
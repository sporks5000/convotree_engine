;(function () {
	'use strict';

	$(document).ready(function(){
		const cte = window.convoTree.launch({
			queue: [1,2,3],
			div: $('.put-things-here'),
			name: 'perltest',
			api_url: 'https://perltest.com/data/',
		});
	});
}());
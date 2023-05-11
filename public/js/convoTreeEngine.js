;(function () {
	'use strict';

	var CTE = {
		instances: {},
		call_api: function(api_url, endpoint, data) {
			var url = api_url + endpoint;

			return $.ajax({
				type: "POST",
				url: url,
				data: JSON.stringify(data),
				contentType: "application/json; charset=utf-8",
				dataType: "json",
				failure: function(errMsg) {
					// ##### TODO: What should I do here?
					console.log({errMsg: errMsg});
				}
			});
		},

		/* Given a div element, initiate a convoTreeEngine instance

		Arguments:
		- ids      - 
		- div      - 
		- name     - 
		- api_url  - 
		- elements - 

		*/
		convoLaunch: function(settings) {
			var div = $(settings.div);
			if (settings.ids && !Array.isArray(settings.ids)) {
				settings.ids = [settings.ids];
			}
			var self = CTE.instances[settings.name] = {
				div: div,
				list: settings.ids,
				name: settings.name,
				api_url: settings.api_url,
				elements: {
					by_id: {},
					by_namecat: {},
				},
				getElements: function(ids) {
					CTE.getElements(this, ids);
				},
			};
			// Each time the current list enters a nested list, we can add it here; each
			// time we get to the end of a list, we just go back to the previous one.
			// ##### TODO: build upon this
			self.curList = [self.list];

			// If we were passed pre-cooked elements, store those
			if (settings.elements) {
				settings.elements.forEach(function(item, index) {
					self.elements.by_id[item.id] = item;
					self.elements.by_namecat[item.namecat] = item;
				});
			}

			// Determine what IDs we still need to pull, and pull them
			let neededIds = [];
			if (settings.ids) {
				settings.ids.forEach(function(item, index) {
					if (!self.elements.by_id[item] && !self.elements.by_namecat[item]) {
						neededIds.push(item);
					}
				});
			}
			if (neededIds.length) {
				CTE.getElements(self, neededIds);
			}

			// Updates to our div
			div.data('cte-name', settings.name);
			div.addClass('cte-container');

			return self;
		},

		// Given our object and an ID or array of IDs, query for those IDs and add them to our object
		getElements: function(self, ids) {
			CTE.call_api(self.api_url, 'element/get', {ids: ids}).done(function(data) {
				for (const [key, value] of Object.entries(data.response)) {
					self.elements.by_id[key] ||= value;
					self.elements.by_namecat[value.namecat] ||= value;
				}
			});
		},
	};

	window.convoTree = window.convoTree || {};
	window.convoTree.inner = CTE;
	window.convoTree.launch = CTE.convoLaunch;
}());


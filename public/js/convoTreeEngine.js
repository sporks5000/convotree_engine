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
		- ids       - 
		- div       - 
		- name      - 
		- api_url   - 
		- elements  - 
		- variables - 

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
				getElement: function(id) {return CTE.getElement(this, id);},
				fetchElements: function(ids, force) {return CTE.fetchElements(this, ids, force);},
				actOnElement: function(id) {return CTE.actOnElement(this, id);},
			};
			self.variables = settings.variables || {};
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
			CTE.fetchElements(self, settings.ids);

			// Updates to our div
			div.data('cte-name', settings.name);
			div.addClass('cte-container');

			return self;
		},

		/* Given our object and an ID or array of IDs, query for the ones needed. Ensure that a
		   resolved jquery deferred object is always returned so that we can act off of it if
		   necessary.

		   An optional third argument is a boolean value indicating whether or not to skip
		   assessing and just pull everything requested - this can be useful, as requesting an
		   ID will also return any associated IDs, so it's possible to have one of the ID in
		   question without necessarily having all of the thing that might be returned. */
		fetchElements: function(self, ids, force) {
			if (typeof force === 'undefined') {
				force = false;
			}
			if (typeof ids === 'undefined' || ids === null) {
				return $.Deferred().resolve();
			}

			if (!Array.isArray(ids)) {
				ids = [ids];
			}

			let neededIds = [];
			if (force === true) {
				neededIds = ids;
			}
			else {
				ids.forEach(function(item, index) {
					if (!self.elements.by_id[item] && !self.elements.by_namecat[item]) {
						neededIds.push(item);
					}
				});
			}

			if (neededIds.length) {
				return CTE.call_api(self.api_url, 'element/get', {ids: neededIds}).done(function(data) {
					for (const [key, value] of Object.entries(data.response)) {
						self.elements.by_id[key] ||= value;
						self.elements.by_namecat[value.namecat] ||= value;
					}
				});
			}

			return $.Deferred().resolve();
		},

		// Return the boject containing element data. Return nothing if it's not in our data
		getElement: function(self, id) {
			if (self.elements.by_id[id]) {
				return self.elements.by_id[id];
			}
			else if (self.elements.by_namecat[id]) {
				return self.elements.by_namecat[id];
			}
		},

		// Given our object and an ID or namecat, act on the corresponding element
		actOnElement: function(self, id) {
			let action;
			if (!self.elements.by_id[id] && !self.elements.by_namecat[id]) {
				/* Note that there is the potential here for a situation where we have a request for
				   an element in flight at the time when we give the command to act on that element.
				   In that circumstance we'll just request it again - should be no big deal. */
				action = self.fetchElements(id);
			}
			action ||= $.Deferred().resolve();

			return action.done(function() {
				const element = self.getElement(id);
				console.log({element:element}); // ##### TODO: remove this
				if (!element) {
					// ##### TODO: Should we throw some kind of error if the element does exist even after we called for it?
					return;
				}
				CTE.parse[element.type](self, element);
			});
		},

		parse: {
			variable: function(self, element) {
				for (let [key, value] of Object.entries(element.json.update)) {
					if (typeof value === 'number') {
						value = String(value);
					}
					else if (value === null) {
						// If it's null, delete the key from the variables hash
						delete self.variables[key];
						continue;
					}

					if (/^[+*\/-]=\s?(-?[1-9][0-9]*|0)(\.[0-9]+)?$/.test(value)) {
						// If the value indicates that we're updating a numerical value. I.E. "+=3"
						let current = self.variables[key];
						if (typeof current === 'string') {
							self.variables[key] = value;
							continue;
						}
						else if (typeof current === 'undefined' || current === null) {
							current = 0;
						}

						const operator = value.substring(0,2);
						const number = Number(value.substring(2));

						if (operator === '+=') {
							current += number;
						}
						else if (operator === '-=') {
							current += number;
						}
						else if (operator === '*=') {
							current *= number;
						}
						else if (operator === '/=') {
							current /= number;
						}

						self.variables[key] = current;
					}
					else if (/^(-?[1-9][0-9]*|0)(\.[0-9]+)?$/.test(value)) {
						// If the value is just a number
						self.variables[key] = Number(value);
					}
					else {
						// If the value is a string
						self.variables[key] = value;
					}
				}
			},
			note: function(self, element) {
				return;
			},
			data: function(self, element) {
				self.fetchElements(element.json.get, true);
			},
			series: function(self, element) {
				/* Note to future self: In addition to queueing things up, we should also re-pull all
				   elements of types that have associated elements, to ensure that their associated
				   elements have been pulled. */
			}
		},
	};

	window.convoTree = window.convoTree || {};
	window.convoTree.inner = CTE;
	window.convoTree.launch = CTE.convoLaunch;
}());


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
		- queue               - 
		- div                 - 
		- name                - 
		- api_url             - 
		- elements            - 
		- variables           - 
		- functions           - 
		- activePromptFrame   - 
		- activeChoiceFrame   - 
		- activeItemFrame     - 
		- inactivePromptFrame - 
		- inactiveChoiceFrame - 
		- inactiveItemFrame   - 
		- defaultPrompt       - 

		*/
		convoLaunch: function(settings) {
			var div = $(settings.div);
			if (settings.queue && !Array.isArray(settings.queue)) {
				settings.queue = [settings.queue];
			}
			var self = CTE.instances[settings.name] = {
				div: div,
				queue: {
					nested_in: null,
					current: settings.queue,
				},
				name: settings.name,
				api_url: settings.api_url,
				elements: {
					by_id: {},
					by_namecat: {},
				},
				getElement: function(id) {return CTE.getElement(this, id);},
				fetchElements: function(ids, force) {return CTE.fetchElements(this, ids, force);},
				actOnElement: function(id) {return CTE.actOnElement(this, id);},
				actOnNextElement: function() {return CTE.actOnNextElement(this);},
			};
			['variables', 'functions'].forEach(function(item, index) {
				self[item] = settings[item] || {};
			});
			['activePromptFrame', 'activeChoiceFrame', 'activeItemFrame', 'inactivePromptFrame', 'inactiveChoiceFrame', 'inactiveItemFrame'].forEach(function(item, index) {
				self[item] = settings[item] || null;
			});
			self.defaultPrompt = settings.defaultPrompt ?? '...';

			// If we were passed pre-cooked elements, store those
			if (settings.elements) {
				settings.elements.forEach(function(item, index) {
					self.elements.by_id[item.id] = item;
					self.elements.by_namecat[item.namecat] = item;
				});
			}

			// Determine what IDs we still need to pull, and pull them
			CTE.fetchElements(self, settings.queue);

			// Updates to our div
			div.data('cte-name', settings.name);
			div.addClass('cte-container');

			return self;
		},

		/* A note on how the queue works:

		   The queue is an object containing two keys: "nested_in" and "current". "Current" is
		   an array containing either element IDs or namecats. We act on these elements one at
		   a time until we reach the end of the array; as we act on the elements we remove them
		   from the array. Some elements will add additional element IDs or namecats to the
		   array. When we reach the end of the array, if "nested_in" is populated, we replace
		   self.queue with self.queue.nested_in, and continue processing from there.

		   If an elements attempts to add IDs to the "current" array, but that array already
		   has at least one ID in it, it will instead nest itself - the opposite of what is
		   described above. */



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
			if (force == true) {
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
				if (!element) {
					// ##### TODO: Should we throw some kind of error if the element does exist even after we called for it?
					return;
				}
				CTE.elementTypes[element.type](self, element);
			});
		},

		actOnNextElement: function(self) {
			/* Get the next element from the queue, then act on that element */
			while (self.queue.nested_in && !self.queue.current.length) {
				self.queue = self.queue.nested_in;
			}

			if (self.queue.current.length) {
				const id = self.queue.current.shift();
				return self.actOnElement(id);
			}
		},

		elementTypes: {
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

				// Always go straight into the next element from this element type
				self.actOnNextElement();
			},
			note: function(self, element) {
				return;
				// Always go straight into the next element from this element type
				self.actOnNextElement();
			},
			data: function(self, element) {
				self.fetchElements(element.json.get, true);
				// Always go straight into the next element from this element type
				self.actOnNextElement();
			},
			series: function(self, element) {
				/* Note to future self: In addition to queueing things up, we should also re-pull all
				   elements of types that have associated elements, to ensure that their associated
				   elements have been pulled. */
			},
			item: function(self, element, additionalArgs) {
				additionalArgs ||= {};
				additionalArgs.active ??= true;
				additionalArgs.type ??= 'item';

				let text = additionalArgs.active == true ? element.json.text : element.json.textx;
				let delay = element.json.delay ?? 500;
				delay = Number(delay);
				let prompt = element.json.prompt ?? true;
				const funcName = element.json.function ?? null;

				// Create the div that will contain the item text
				let htmlDiv = $('<div>');

				if (typeof text === 'string') {
					text = {text: text};
				}

				// Determine what classes we will be using and then apply thme to the div if applicable
				let frameClass;
				let frame = text.frame;
				if (typeof frame === 'undefined') {
					if (additionalArgs.active == true) {
						if (additionalArgs.type === 'choice') {
							frameClass = 'convoTreeEngine-choice-frame convoTreeEngine-active-frame';
							frame = self.activeChoiceFrame;
						}
						if (additionalArgs.type === 'prompt') {
							frameClass = 'convoTreeEngine-prompt-frame convoTreeEngine-active-frame';
							frame = self.activePromptFrame;
						}
						else {
							frameClass = 'convoTreeEngine-item-frame convoTreeEngine-active-frame';
							frame = self.activeItemFrame;
						}
					}
					else {
						if (additionalArgs.type === 'choice') {
							frameClass = 'convoTreeEngine-choice-frame convoTreeEngine-inactive-frame';
							frame = self.inactiveChoiceFrame;
						}
						if (additionalArgs.type === 'prompt') {
							frameClass = 'convoTreeEngine-prompt-frame convoTreeEngine-inactive-frame';
							frame = self.inactivePromptFrame;
						}
						else {
							frameClass = 'convoTreeEngine-item-frame convoTreeEngine-inactive-frame';
							frame = self.inactiveItemFrame;
						}
					}
				}
				if (frame && frame.length) {
					htmlDiv.addClass(frame);
				}
				if (frameClass.length) {
					htmlDiv.addClass(frameClass);
				}

				// Apply hover text if applicable
				if (typeof text.hover !== 'undefined') {
					let hover = CTE.utils.escapeStr(text.hover);
					hover = CTE.utils.expandHoverTextVariables(self, hover);
					htmlDiv.attr('title', hover);
				}

				let htmlSpan = $('<span>');
				if (typeof text.classes !== 'undefined') {
					htmlSpan.addClass(text.classes);
				}

				// The text for an item can be provided in one of two formats. Determine which is
				// the case, put it together, and add it to the htmlDiv
				if (Array.isArray(text.text)) {
					htmlSpan = CTE.utils.handleNestedItemText(self, htmlSpan, text.text);
				}
				else {
					const speaker = text.speaker || '';
					const parsedText = CTE.utils.parseItemText(self, speaker, text.text);
					htmlSpan.html(parsedText);
				}
				htmlDiv.append(htmlSpan);

				// If we're in anythin other than an item , process against the function (if any), and
				// then return the htmlDiv. We ignore both 'delay' and 'prompt'.
				if (additionalArgs.type !== 'item') {
					if (funcName !== null) {
						if (self.functions[funcName]) {
							htmlDiv = self.functions[funcName]({
								self: self,
								htmlDiv: htmlDiv,
								element: element,
								active: additionalArgs.active,
							});
						}
					}
					return htmlDiv;
				}

				setTimeout(function() {
					// If there is a function, we want to process it right before we display rather
					// than before we start the delay.
					if (funcName !== null) {
						if (self.functions[funcName]) {
							htmlDiv = self.functions[funcName]({
								self: self,
								htmlDiv: htmlDiv,
								element: element,
								active: additionalArgs.active,
							});
						}
					}

					self.div.append(htmlDiv);
					if (prompt == false) {
						return self.actOnNextElement();
					}
					else if (prompt == true) {
						prompt = self.defaultPrompt;
					}

					// Generate the div for the prompt in the same way that we generate the div for
					// the item itself
					let promptDiv = CTE.elementTypes.item(self, {
						json: {
							text: prompt,
						},
					}, {type: 'prompt'});

					self.div.append(promptDiv);
				}, delay);
			},
		},

		utils: {
			escapeStr: function(str) {
				/* Convert the following characters to their html-code equivalents: "&", "<", ">" */
				return str.replace(/&/g, '&amp;')
					.replace(/</g, '&lt;')
					.replace(/>/g, '&gt;');
			},
			variableValueToDisplay: function(value) {
				/* Given the value of a variable, prepare it to be displayed as part of a item. Make
				   sure it's defined, make sure it's a string, make sure it's escaped appropriately,
				   etc. */
				value ??= '[UNDEFINED]';
				value = String(value);
				value = CTE.utils.escapeStr(value);
				return value.replace(/\r?\n\r?/g, '<br>')
					.replace(/"/g, '&quot;');
			},
			expandHoverTextVariables: function(self, hover) {
				/* Given a string of text that contains variable names contained within square brackets,
				   replace each of those varaibles with the value of the variable. */
				let vars = hover.match(/\[[a-zA-Z0-9_.]+\]/g);
				if (!vars || !vars.length) {
					return hover;
				}
				let chunks = hover.split(/\[[a-zA-Z0-9_.]+\]/);
				let modifiedHover = chunks.shift();

				while (vars.length) {
					let varName = vars.shift();
					let chunk = chunks.shift();
					varName = varName.substring(1, varName.length - 1);

					let value = self.variables[varName];
					// The below code reproduces SOME of the actions within variableValueToDisplay.
					// Specifically we do NOT want to replace linebreaks with '<br>' tags.
					value ??= '[UNDEFINED]';
					value = String(value);
					value = CTE.utils.escapeStr(value);
					value = value.replace(/"/g, '&quot;');

					modifiedHover += value + chunk;
				}

				return modifiedHover;
			},
			parseItemText: function(self, speaker, text) {
				/* Given a text string containing minimal markup, parse that markup and
				   return a string of HTML*/
				// In theory we can rely on none of the text being processed in this way
				// including control characters, so we will be using them as placeholders.
				text = text.replace(/[\x01-\x04]/g, '') //remove the control characters we're using
					.replace(/\\\\/g, "\x00")         // replace all escaped backslashes
					.replace(/\\\[/g, "\x01")         // replace all escaped opening square brackets
					.replace(/\\\]/g, "\x02");        // replace all escaped closing square brackets

				// Separate out the variables; replace them with placeholders.
				let vars = text.match(/\[[a-zA-Z0-9_.]+\]/g);
				text = text.replace(/\[[a-zA-Z0-9_.]+\]/g, "\x03")
					.replace(/\x01/g, '[')  // put opening square brackets back (unescaped this time)
					.replace(/\x02/g, ']'); // put closing square brackets back (unescaped this time)

				// Make sure that we're html safe
				text = CTE.utils.escapeStr(text);

				text = text.replace(/\r?\n\r?/g, '<br>')    // newline characters becomes linebreaks
					.replace(/\\_/g, "\x01")              // replace all escaped underscores
					.replace(/_([^_]*)_/g, "<i>$1</i>")   // italicize text within underscores
					.replace(/\x01/g, '_')                // put underscores back, unescaped
					.replace(/\\\*/g, "\x01")             // replace all escaped asterisks
					.replace(/\*([^*]*)\*/g, "<b>$1</b>") // bold text within asterisks
					.replace(/\x01/g, '*')                // put asterisks back
					.replace(/\\"/g, "\x01")              // replace all escaped quotes
					.replace(/"([^"]*)"/g, '<span class="' + speaker + '">&quot;' + "$1" + '&quot;</span>') // quotes in spans
					.replace(/\x01/g, '&quot;')           // bring back quotation marks
					.replace(/\x00/g, '\\');              // bring back backslashes

				// replace variable names with their values
				if (vars) {
					while (vars.length) {
						let varName = vars.shift();
						varName = varName.substring(1, varName.length - 1);
						let value = self.variables[varName];
						value = CTE.utils.variableValueToDisplay(value);
						text = text.replace("\x03", value);
					}
				}

				return text;
			},
			handleNestedItemText: function(self, htmlSpan, text) {
				/* Given item text that is in the "nested array" format, process it out into the html that
				   we'll be displaying. See modules/ConvoTreeEngine/ElementExamples.pm for details */
				text.forEach(function(block, index) {
					let classes = block[0];
					let content = block[1];
					let span = $('<span>')
					if (classes !== null) {
						span.addClass(classes);
					}
					if (content !== null) {
						if (Array.isArray(content)) {
							// It's more nested arrays
							span = CTE.utils.handleNestedItemText(self, span, content);
						}
						else {
							// It's a string of text, for which we'll do the bare minimal parsing
							content = CTE.utils.variableValueToDisplay(content);
							span.append(content);
						}
					}
					else {
						// null content means that there is a third element and it is the name of a variable
						let varName = block[2];
						content = self.variables[varName];
						content = CTE.utils.variableValueToDisplay(content);
						span.append(content);
					}
					htmlSpan.append(span);
				});

				return htmlSpan;
			},
		},
	};

	window.convoTree = window.convoTree || {};
	window.convoTree.inner = CTE;
	window.convoTree.launch = CTE.convoLaunch;
}());


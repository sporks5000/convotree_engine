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
					seen: {},
					pulled: {},
				},
				getElement: function(id) {return CTE.getElement(this, id);},
				fetchElements: function(ids) {return CTE.fetchElements(this, ids);},
				actOnElement: function(id) {return CTE.actOnElement(this, id);},
				actOnNextElement: function() {return CTE.actOnNextElement(this);},
				hasSeenElement: function(ident) {return CTE.hasSeenElement(this, ident);},
				markElementSeen: function(element) {return CTE.markElementSeen(this, element);},
				addToQueue:function(idents) {return CTE.addToQueue(this, idents);},
				queueLength: function() {return CTE.queueLength(this)},
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
		   necessary. */
		fetchElements: function(self, idents) {
			if (typeof idents === 'undefined' || idents === null) {
				return $.Deferred().resolve();
			}

			if (!Array.isArray(idents)) {
				idents = [idents];
			}

			let needed = []
			let requested = {};
			idents.forEach(function(ident, index) {
				if (!self.elements.pulled[ident]) {
					needed.push(ident);
					requested[ident] = true;
				}
			});

			if (needed.length) {
				return CTE.call_api(self.api_url, 'element/get', {ids: needed}).done(function(data) {
					for (const [key, value] of Object.entries(data.response)) {
						self.elements.by_id[key] ||= value;
						self.elements.by_namecat[value.namecat] ||= value;
						if (requested[key] === true || requested[value.namecat] === true) {
							// If the item was one that we specifically requested, note it has been specifically
							// requested so that we won't ever request it again.
							self.elements.pulled[key] = true;
							self.elements.pulled[value.namecat] = true;
						}
					}
				});
			}

			return $.Deferred().resolve();
		},

		// Return the object containing element data. Return nothing if it's not in our data
		getElement: function(self, ident) {
			if (self.elements.by_id[ident]) {
				return self.elements.by_id[ident];
			}
			else if (self.elements.by_namecat[ident]) {
				return self.elements.by_namecat[ident];
			}
		},

		// Given our object and an ID or namecat, act on the corresponding element
		actOnElement: function(self, ident) {
			let action;
			if (!self.elements.by_id[ident] && !self.elements.by_namecat[ident]) {
				/* Note that there is the potential here for a situation where we have a request for
				   an element in flight at the time when we give the command to act on that element.
				   In that circumstance we'll just request it again - should be no big deal. */
				action = self.fetchElements(ident);
			}
			action ||= $.Deferred().resolve();

			return action.done(function() {
				const element = self.getElement(ident);
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

		addToQueue: function(self, idents) {
			/* Given an element identifier or an array of element identifiers, add them to the
			   queue of elements to be visited. */
			/* Note: One of the design decisions of this project was giving control to the
			   creator over when element data is pulled from the backend. While some steps of
			   that have been added automatically in other places to ensure that there was no
			   interruption of flow, it was decided that adding additional pieces of it within
			   the "addToQueue" function was not necessary. */
			if (typeof idents === 'undefined' || idents === null) {
				return;
			}
			if (!Array.isArray(idents)) {
				idents = [idents];
			}

			if (self.queue.current.length) {
				// If there are already things in the queue, make a nested list to process through
				// before returning to the list that's currently present.
				let queue = self.queue;
				self.queue = {
					nested_in: queue,
					current: idents,
				};
				return;
			}

			self.queue.current = idents;
		},

		hasSeenElement: function(self, ident) {
			/* Given an element or an element identiiyer, determine if that element is in the
			   list of elements seen by the user */
			if (typeof ident === 'object') {
				// If we were passed an element data structure, use the ID from it
				ident = ident.id;
			}
			if (self.elements.seen[ident] == true) {
				return true;
			}
			return false;
		},

		markElementSeen: function(self, element, unsee) {
			/* Given an element or an element identifier, mark that element as having been seen by
			   the user. Alternatively, if a third argument of "true" is passed, remove the
			   indicator that the element has been seen.*/
			unsee ??= false;
			if (typeof element !== 'object') {
				// If we were passed an ID or a namecat, get the actual element data structure
				element = self.getElement(element);
				if (!element) {
					return;
				}
			}

			if (unsee == true) {
				delete self.elements.seen[element.id];
				delete self.elements.seen[element.namecat];
				return;
			}

			self.elements.seen[element.id] = true;
			self.elements.seen[element.namecat] = true;
		},

		queueLength: function(self) {
			/* Return the number of elements currently present before ending the queue */
			let qLength = self.queue.current.length;
			let current = self.queue;
			while(current.nested_in) {
				current = current.nested_in;
				length += current.current.length;
			}

			return qLength;
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
						const number = Number(value.substring(2).trim());

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
			elements: function(self, element) {
				if ('queue' in element.json) {
					self.addToQueue(element.json.queue);
				}
				if ('get' in element.json) {
					self.fetchElements(element.json.get);
				}
				// Always go straight into the next element from this element type
				self.actOnNextElement();
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

				// Determine what classes we will be using and then apply them to the div if applicable
				let activeString = additionalArgs.active == true ? 'active' : 'inactive';
				let frameClass = 'convoTreeEngine-' + additionalArgs.type + '-frame convoTreeEngine-' + activeString + '-frame';
				let frame = text.frame;
				if (typeof frame === 'undefined') {
					const type = additionalArgs.type.charAt(0).toUpperCase() + additionalArgs.type.slice(1);
					frame = self[activeString + type + 'Frame'];
				}
				if (frame && frame.length) {
					htmlDiv.addClass(frame);
				}
				htmlDiv.addClass(frameClass);
				if ('id' in element) {
					// There are some instances where we might pass in a fake element, so make sure
					// that an ID is actually present.
					htmlDiv.addClass('convoTreeEngine-element-' + String(element.id));
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

					if (prompt == false || prompt === "0" || self.queueLength() === 0) {
						// If we're not prompting, go straight to the next element in the queue.
						// If there are no elements in the queue (regardless of whether we would
						// typically prompt), reach the end.
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

					htmlDiv.append(promptDiv);
					CTE.listeners.itemPrompt(self, htmlDiv);
					self.div.append(htmlDiv);
					self.markElementSeen(element);
				}, delay);
			},
			if: function(self, element) {
				let condBlocks = element.json.cond;
				for (var i = 0; i < condBlocks.length; i++) {
					const conditionIsMet = CTE.utils.assessCondition(self, condBlocks[i][0], element, true);
					if (conditionIsMet == true) {
						self.addToQueue(condBlocks[i][1]);
						break;
					}
				};

				self.actOnNextElement();
			},
			choice: function(self, element) {
				let needed = [];
				let choices = [];
				element.json.choices.forEach(function(block, index) {
					needed.push(block.element);
					choices.push({
						data: block,
						active: false,
					});
				});

				// Theoretically we already have the item elements for all of the choices, but just to be safe...
				let fetch = self.fetchElements(needed);

				let delay = element.json.delay ?? 500;
				delay = Number(delay);

				let first = true;
				choices.forEach(function(choice, index) {
					choice.active = CTE.utils.assessCondition(self, choice.data.cond, choice.data, first);
					if (choice.active == true) {
						// After at least one condition is active, none of the rest can be "first"
						first = false;
					}
				});

				fetch.done(function() {
					let choicesDiv = $('<div>').addClass('convoTreeEngine-choices-group');
					if ('classes' in element.json) {
						choicesDiv.addClass(element.json.classes);
					}
					if ('classes' in choice.data) {
						choicesDiv.addClass(choice.data.classes);
					}

					choices.forEach(function(choice, index) {
						choice.element = self.getElement(choice.data.element);
						if (choice.active == true || choice.data.display_inactive == true) {
							let choiceDiv = CTE.elementTypes.item(self, choice.element, {type: 'choice', active: choice.active});
							if (choiceDiv !== null) {
								// If the user has set a function as part of assessing the choice, it's possible that
								// they could have it return null (I.E. even though the settings and conditions for
								// the choice would otherwise have it displayed, they do not want it to be displayed).
								choicesDiv.data(choice.data);
								choicesDiv.append(choiceDiv);
							}
						}
					});

					CTE.listeners.choices(self, choicesDiv);
					setTimeout(function() {
						CTE.listeners.choices(self, choicesDiv);
						self.div.append(choicesDiv);
					}, delay);
				});
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
				text = text.replace(/[\x01-\x07]/g, '') //remove the control characters we're using
					.replace(/\\\\/g, "\x00")         // replace all escaped backslashes
					.replace(/\\\[/g, "\x01")         // replace all escaped opening square brackets
					.replace(/\\\]/g, "\x02")         // replace all escaped closing square brackets
					.replace(/\\\(/g, "\x03")         // escaped opening parentheses
					.replace(/\\\)/g, "\x04");        // escaped closing parentheses

				// Separate out the variables; replace them with placeholders.
				// Use lookahead to ensure we're not matching "](", because that would indicate an html
				// link.
				let vars = text.match(/\[[a-zA-Z0-9_.]+\](?!\()/g);
				text = text.replace(/\[[a-zA-Z0-9_.]+\](?!\()/g, "\x07")
					.replace(/\x01/g, '[')  // put opening square brackets back (unescaped this time)
					.replace(/\x02/g, ']'); // put closing square brackets back (unescaped this time)

				// Note that the way we're handling links, if they cannot contain backslashes, square
				// brackets, or parentheses, those characters must be preceeded by a backslash.
				let links = text.match(/\[[^\]]+\]\(http[^\s]+\)/g);
				text = text.replace(/\[([^\]]+)\]\(http[^\s]+\)/g, "\x05$1\x06")
					.replace(/\x03/g, '(')
					.replace(/\x04/g, ')');

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
						text = text.replace("\x07", value);
					}
				}

				if (links) {
					while (links.length) {
						let link = links.shift()
							.replace(/\[[^\]]+\]\((http[^\s]+)\)/, "$1")
							.replace(/\x03/g, '(')
							.replace(/\x04/g, ')')
							.replace(/\x01/g, '[')
							.replace(/\x02/g, ']')
							.replace(/\x00/g, '\\');
						text = text.replace(/\x05([^\x06]+)\x06/, '<a href="' + link + '">' + "$1" + '</a>');
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
			assessCondition: function(self, cond, data, first) {
				if (typeof cond === 'undefined' || cond === null) {
					// No condition always means that the condition is met
					return true;
				}

				if (Array.isArray(cond)) {
					// If we're given an array, process each item in it. All items must pass for the condition to be met
					for (var i = 0; i < cond.length; i++) {
						let resp = CTE.utils.assessCondition(self, cond[i], data, first);
						if (resp == false) {
							// One of them is false, so it's ALL false
							return false;
						}
					}
					return true;
				}

				if (typeof cond === 'string') {
					return CTE.utils.assessConditionString(self, cond, data, first);
				}
				else {
					// If any of the keys in the object return false, then we consider the entire object to be false
					if ('not' in cond) {
						let resp = CTE.utils.assessCondition(self, cond['not'], data, first);
						if (resp == true) {
							return false;
						}
					}
					if ('and' in cond) {
						let resp = CTE.utils.assessCondition(self, cond['and'], data, first);
						if (resp == false) {
							return false;
						}
					}
					if ('or' in cond) {
						if (!Array.isArray(cond['or'])) {
							cond['or'] = [cond['or']];
						}
						for (var i = 0; i < cond['or'].length; i++) {
							let resp = CTE.utils.assessCondition(self, cond['or'][i], data, first);
							if (resp == true) {
								// No need to test any more conditions
								break;
							}
						}
					}
					if ('xor' in cond) {
						if (!Array.isArray(cond['xor'])) {
							cond['xor'] = [cond['xor']];
						}
						let checks = 0;
						for (var i = 0; i < cond['xor'].length; i++) {
							let resp = CTE.utils.assessCondition(self, cond['xor'][i], data, first);
							if (resp == true) {
								checks++;
								if (checks > 1) {
									return false;
								}
							}
						}
						if (checks === 0) {
							return false;
						}
					}
				}

				// If we've gotten this far, the condition passed
				return true;
			},
			assessConditionString: function(self, cond, data, first) {
				// Set aside any quoted strings
				let quoted = cond.match(/('[^']*'|"[^"]*")/g);
				cond = cond.replace(/('[^']*'|"[^"]*")/g, "\x00");

				// Split by "or" first, then by "and"
				let orStrings = cond.split('|');
				for (var i = 0; i < orStrings.length; i++) {
					let pass = true;
					let andStrings = orStrings[i].split('&');
					for (var j = 0; j < andStrings.length; j++) {
						if (pass == true) {
							let inverse = false;
							andStrings[j] = andStrings[j].trim();
							if (andStrings[j].substring(0, 1) === '!') {
								inverse = true;
								andStrings[j] = andStrings[j].replace(/^!\s*/, '');
							}

							if (/^seen\s+:/i.test(andStrings[j])) {
								let ident = andStrings[j].replace(/^seen\s*:\s*/i, '').replace(/\s*$/, '');
								if (!self.hasSeenElement(ident)) {
									pass = false;
								}
							}
							else if (/^function\s*:/i.test(andStrings[j])) {
								const funcName = andStrings[j].replace(/^function\s*:\s*/i, '').replace(/\s*$/, '');
								if (self.functions[funcName]) {
									// Run the function, passing in the data from the condition
									pass = !!self.functions[funcName]({
										self: self,
										condData: data,
									});
								}
							}
							else if (/^first$/i.test(andStrings[j])) {
								pass = first;
							}
							else {
								const [operator] = andStrings[j].match(/[!><=]=|[=><]|!==/g);
								let [varName, condValue] = andStrings[j].split(/[!><=]=|[=><]|!==/);
								varName = varName.trim();
								condValue = condValue.trim();

								// Add back in any quoted strings
								while (/\x00/.test(condValue)) {
									let quotedString = quoted.shift();
									quotedString = quotedString.substring((1, quotedString.length - 1));
									condValue = condValue.replace("\x00", quotedString);
								}

								let varValue = self.variables[varName];
								if (/[<>]|'=='/.test(operator)) {
									// If the operator indicates that both should be a number...
									if (/^(-?[1-9][0-9]*|0)(\.[0-9]+)?$/.test(condValue) || /^(-?[1-9][0-9]*|0)(\.[0-9]+)?$/.test(varValue)) {
										// ...and they both look like a number, make sure they're stored as numbers
										condValue = Number(condValue);
										varValue = Number(varValue);
									}
									else {
										// If either/both of them don't look like a number, fail automatically
										condValue = true;
										varValue = false;
									}
								}
								else if (/^(-?[1-9][0-9]*|0)(\.[0-9]+)?$/.test(condValue) && /^(-?[1-9][0-9]*|0)(\.[0-9]+)?$/.test(varValue)) {
									// If both the variable value and the condition value look like numbers, make them numbers
									condValue = Number(condValue);
									varValue = Number(varValue);
								}
								else {
									// Otherwise make them both strings
									condValue = String(condValue);
									varValue = String(varValue);
								}

								if (operator === '=' || operator === '==') {
									if (condValue !== varValue) {
										pass = false;
									}
								}
								else if (operator === '!=' || operator === '!==') {
									if (condValue === varValue) {
										pass = false;
									}
								}
								else if (operator === '>') {
									if (condValue <= varValue) {
										pass = false;
									}
								}
								else if (operator === '<') {
									if (condValue >= varValue) {
										pass = false;
									}
								}
								else if (operator === '>=') {
									if (condValue < varValue) {
										pass = false;
									}
								}
								else if (operator === '<=') {
									if (condValue > varValue) {
										pass = false;
									}
								}
							}

							if (inverse == true) {
								pass = !pass;
							}
						}
						else {
							// Even if we know that this portion won't pass because one of the other
							// parts of the "and "condition failed, we still need to discard any
							// quoted strings.
							while (/\x00/.test(andStrings[j])) {
								quoted.shift();
							}
						}
					}

					if (pass == true) {
						return true;
					}
				}

				return false;
			},
		},

		listeners: {
			itemPrompt: function(self, htmlDiv) {
				htmlDiv.on('click', '.convoTreeEngine-prompt-frame', function() {
					// ##### TODO: Will child elements inherit this?
					$(this).closest('.convoTreeEngine-prompt-frame').remove();
					self.actOnNextElement();
				});
				htmlDiv.find('.convoTreeEngine-prompt-frame').css('cursor','pointer');
			},
			choices: function(self, choicesDiv) {
				choicesDiv.on('click', '.convoTreeEngine-choice-frame', function() {
					let choice = $(this).closest('.convoTreeEngine-choice-frame');
					let choiceData = choice.data();

					self.markElementSeen(choiceData.element);
					self.addToQueue(choiceData.then);

					// Remove all of the choices other than this one
					choice.closest('.convoTreeEngine-choices-group').find('.convoTreeEngine-choice-frame').not(choice).remove();

					self.actOnNextElement();
				});
				choicesDiv.find('.convoTreeEngine-choice-frame').css('cursor','pointer');
			},
		},
	};

	window.convoTree = window.convoTree || {};
	window.convoTree.inner = CTE;
	window.convoTree.launch = CTE.convoLaunch;
}());


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
				},
				getElement: function(id) {return CTE.getElement(this, id);},
				fetchElements: function(ids, force) {return CTE.fetchElements(this, ids, force);},
				actOnElement: function(id) {return CTE.actOnElement(this, id);},
				actOnNextElement: function() {return CTE.actOnNextElement(this);},
				hasSeenElement: function(ident) {return CTE.hasSeenElement(this, ident);},
				markElementSeen: function(element) {return CTE.markElementSeen(this, element);},
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

			CTE.setupEventListeners(self, div);

			// Updates to our div
			div.data('cte-name', settings.name);
			div.addClass('cte-container');

			return self;
		},

		setupEventListeners: function(self, div) {
			// ##### TODO: Event listeners for prompts and choices
			// ##### TODO: For choices, mark the chosen option as seen.
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

		hasSeenElement: function(self, ident) {
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
						// ##### TODO: trim unless the value starts and ends with quotes
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
				// ##### TODO: this
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
					if (prompt == false || prompt === "0") {
						// If we're not prompting, go straight to the next element in the queue
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
					self.markElementSeen(element);
				}, delay);
			},
			if: function(self, element) {
				// ##### TODO: This
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
					choice.data.disp_inactive = CTE.utils.convertFromPerlBoolean(choice.data.disp_inactive);
					choice.active = CTE.utils.assessCondition(self, choice.data.cond, choice.data, first);
					if (choice.active == true) {
						// After at least one condition is active, none of the rest can be "first"
						first = false;
					}
				});

				fetch.done(function() {
					let choicesDiv = $('<div>');
					if ('classes' in element.json) {
						choicesDiv.addClass(element.json.classes);
					}

					choices.forEach(function(choice, index) {
						choice.element = self.getElement(choice.data.element);
						if (choice.active == true || choice.data.display_inactive == true) {
							let choiceDiv = CTE.elementTypes.item(self, choice.element, {type: 'choice', active: choice.active});
							if (choiceDiv !== null) {
								// If the user has set a function as part of assessing the choice, it's possible that
								// they could have it return null (I.E. even though the settings and conditions for
								// the choice would otherwise have it displayed, they do not want it to be displayed).
								choicesDiv.append(choiceDiv);
							}
						}
					});

					setTimeout(function() {
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
			convertFromPerlBoolean: function(value) {
				/* Given a value recieved from a server response that should be boolean, return whether
				   to interpret it as true or false. The key difference between Perl's in terpretation
				   of truthiness and JavaScript's interpretation of truthiness is that Perl has a looser
				   differentiation between strings and numbers and as such the string "0" needs to be
				   interpreted as false (where as JS would interpret it as true. */
				if (typeof value === 'string' && value === '0') {
					return false;
				}
				return !!value;
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
							}
						}
						if (checks !== 1) {
							return false;
						}
					}
					if ('xand' in cond) {
						if (!Array.isArray(cond['xand'])) {
							cond['xand'] = [cond['xand']];
						}
						let checks = 0;
						for (var i = 0; i < cond['xand'].length; i++) {
							let resp = CTE.utils.assessCondition(self, cond['xand'][i], data, first);
							if (resp == true) {
								checks++;
							}
						}
						if (checks === 0) {
							return false;
						}
						else if (checks === cond['xand'].length) {
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
								const [operator] = andStrings[j].match(/[!><]=|[=><]/g);
								let [varName, condValue] = andStrings[j].split(/[!><]=|[=><]/);
								varName = varName.trim();
								condValue = condValue.trim();

								// Add back in any quoted strings
								while (/\x00/.test(condValue)) {
									let quotedString = quoted.shift();
									quotedString = quotedString.substring((1, quotedString.length - 1));
									condValue = condValue.replace("\x00", quotedString);
								}

								let varValue = self.variables[varName];
								if (/[<>]/.test(operator)) {
									// If the operator indicates that it should be a number, make it a number
									condValue = Number(condValue);
									varValue = Number(varValue);
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

								if (operator === '=') {
									if (condValue !== varValue) {
										pass = false;
									}
								}
								else if (operator === '!=') {
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
	};

	window.convoTree = window.convoTree || {};
	window.convoTree.inner = CTE;
	window.convoTree.launch = CTE.convoLaunch;
}());


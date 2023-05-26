;(function () {
	'use strict';

	$(document).ready(function(){
		const cte = window.convoTree.launch({
			queue: [1,3,2,3,6],
			div: $('.put-things-here'),
			name: 'perltest',
			api_url: 'https://perltest.com/data/',
			elements: [
				{
					id: 1,
					namecat: 'test:1',
					type: 'variable',
					json: {
						update: {
							value1: 30,
							value2: 10,
							value3: 'Mike',
						},
					},
				},
				{
					id: 2,
					namecat: 'test:2',
					type: 'variable',
					json: {
						update: {
							value1: '+=2',
							value2: '/=2',
							value3: 'Jeff',
						}
					},
				},
				{
					id: 3,
					namecat: 'test:3',
					type: 'item',
					json: {
						text: 'Current variable values: *value1* = "[value1]"; *value2* = "[value2]"; *value3* = "[value3]".',
						delay: 0,
					},
				},
				{
					id: 4,
					namecat: 'test:4',
					type: 'item',
					json: {
						text: 'This will set *value1* to "1"',
					},
				},
				{
					id: 5,
					namecat: 'test:5',
					type: 'item',
					json: {
						text: 'This will set *value2* to "1"',
					},
				},
				{
					id: 6,
					namecat: 'test:6',
					type: 'choice',
					json: {
						choices: [
							{
								cond: null,
								element: 4,
								then: [8, 11],
							},
							{
								cond: null,
								element: 5,
								then: [9, 11],
							},
							{
								cond: 'value1==1|value2==1',
								element: 7,
								then: [10, 11],
							},
						],
					},
				},
				{
					id: 7,
					namecat: 'test:7',
					type: 'item',
					json: {
						text: {
							text: 'This is a *secret* option',
						},
					},
				},
				{
					id: 8,
					namecat: 'test:8',
					type: 'variable',
					json: {
						update: {
							value1: 1,
						}
					},
				},
				{
					id: 9,
					namecat: 'test:9',
					type: 'variable',
					json: {
						update: {
							value2: 1,
						}
					},
				},
				{
					id: 10,
					namecat: 'test:10',
					type: 'variable',
					json: {
						update: {
							value3: 'Conrad',
						}
					},
				},
				{
					id: 11,
					namecat: 'test:11',
					type: 'if',
					json: {
						cond: [
							[
								'value3=Conrad',
								[12,13,14,15,16],
							],
							[
								'value1==1',
								[3,6],
							],
							[
								null,
								[3,6],
							],
						],
					},
				},
				{
					id: 12,
					namecat: 'test:12',
					type: 'variable',
					json: {
						update: {
							value1: 1,
						},
					},
				},
				{
					id: 13,
					namecat: 'test:13',
					type: 'variable',
					json: {
						update: {
							value1: '+=1',
						},
					},
				},
				{
					id: 14,
					namecat: 'test:14',
					type: 'item',
					json: {
						text: {
							text: [
								[
									null,
									"We're going to change ",
								],
								[
									'bluetext',
									'some CSS',
								],
								[
									null,
									', ',
								],
								[
									null,
									null,
									'value3',
								],
								[
									null,
									'!',
								],
							],
						},
					},
				},
				{
					id: 15,
					namecat: 'test:15',
					type: 'display',
					json: {
						mine: {
							'.bluetext': 'color: #0000FF;',
						},
						delay: 0,
					},
				},
				{
					id: 16,
					namecat: 'test:16',
					type: 'if',
					json: {
						cond: [
							[
								'value1==2',
								[13,14,15,16],
							],
							[
								null,
								17,
							],
						],
					},
				},
				{
					id: 17,
					namecat: 'test:17',
					type: 'item',
					json: {
						text: {
							text: 'I wanted to tell you "I have run out of things to say" :(',
							speaker: 'bluetext'
						}
					},
				},
/*
				{
					id: 18,
					namecat: 'test:18',
					type: '',
					json: {

					},
				},
				{
					id: 19,
					namecat: 'test:19',
					type: '',
					json: {

					},
				},
				{
					id: 20,
					namecat: 'test:20',
					type: '',
					json: {

					},
				},
				{
					id: 21,
					namecat: 'test:21',
					type: '',
					json: {

					},
				},
				{
					id: 22,
					namecat: 'test:22',
					type: '',
					json: {

					},
				},
				{
					id: 23,
					namecat: 'test:23',
					type: '',
					json: {

					},
				},
				{
					id: 24,
					namecat: 'test:24',
					type: '',
					json: {

					},
				},
				{
					id: 25,
					namecat: 'test:25',
					type: '',
					json: {

					},
				},
				{
					id: 26,
					namecat: 'test:26',
					type: '',
					json: {

					},
				},
				{
					id: 27,
					namecat: 'test:27',
					type: '',
					json: {

					},
				},
				{
					id: 28,
					namecat: 'test:28',
					type: '',
					json: {

					},
				},
				{
					id: 29,
					namecat: 'test:29',
					type: '',
					json: {

					},
				},
				{
					id: 30,
					namecat: 'test:30',
					type: '',
					json: {

					},
				},
				{
					id: 31,
					namecat: 'test:31',
					type: '',
					json: {

					},
				},
				{
					id: 32,
					namecat: 'test:32',
					type: '',
					json: {

					},
				},
				{
					id: 33,
					namecat: 'test:33',
					type: '',
					json: {

					},
				},
				{
					id: 34,
					namecat: 'test:34',
					type: '',
					json: {

					},
				},
				{
					id: 35,
					namecat: 'test:35',
					type: '',
					json: {

					},
				},
				{
					id: 36,
					namecat: 'test:36',
					type: '',
					json: {

					},
				},
				{
					id: 37,
					namecat: 'test:37',
					type: '',
					json: {

					},
				},
				{
					id: 38,
					namecat: 'test:38',
					type: '',
					json: {

					},
				},
				{
					id: 39,
					namecat: 'test:39',
					type: '',
					json: {

					},
				},
				{
					id: 40,
					namecat: 'test:40',
					type: '',
					json: {

					},
				},
				{
					id: 41,
					namecat: 'test:41',
					type: '',
					json: {

					},
				},
				{
					id: 42,
					namecat: 'test:42',
					type: '',
					json: {

					},
				},
				{
					id: 43,
					namecat: 'test:43',
					type: '',
					json: {

					},
				},
				{
					id: 44,
					namecat: 'test:44',
					type: '',
					json: {

					},
				},
				{
					id: 45,
					namecat: 'test:45',
					type: '',
					json: {

					},
				},
				{
					id: 46,
					namecat: 'test:46',
					type: '',
					json: {

					},
				},
				{
					id: 47,
					namecat: 'test:47',
					type: '',
					json: {

					},
				},
*/
			],
		});

		cte.actOnNextElement();
	});
}());
const types = [
	'build',
	'chore',
	'ci',
	'docs',
	'feat',
	'fix',
	'perf',
	'refactor',
	'revert',
	'style',
	'test',
];

export default {
	parserPreset: {
		name: 'refined-github-conventional-commits',
		parserOpts: {
			headerPattern: /^(\w+)(?:\((.+?)\))?!?: *(.*)$/,
			breakingHeaderPattern: /^(\w+)(?:\((.+?)\))?!: *(.*)$/,
			headerCorrespondence: ['type', 'scope', 'subject'],
			noteKeywords: ['BREAKING CHANGE', 'BREAKING-CHANGE'],
		},
	},
	rules: {
		'body-leading-blank': [1, 'always'],
		'body-max-line-length': [2, 'always', 100],
		'footer-leading-blank': [1, 'always'],
		'footer-max-line-length': [2, 'always', 100],
		'header-max-length': [2, 'always', 72],
		'header-trim': [2, 'always'],
		'subject-case': [
			2,
			'never',
			['sentence-case', 'start-case', 'pascal-case', 'upper-case'],
		],
		'subject-empty': [2, 'never'],
		'subject-full-stop': [2, 'never', '.'],
		'type-case': [2, 'always', 'lower-case'],
		'type-empty': [2, 'never'],
		'type-enum': [2, 'always', types],
	},
};

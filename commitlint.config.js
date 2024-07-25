const Configuration = {
    /*
     * Resolve and load @commitlint/config-conventional from node_modules.
     * Referenced packages must be installed
     */
    extends: ['@commitlint/config-conventional'],
    /*
     * Resolve and load conventional-changelog-atom from node_modules.
     * Referenced packages must be installed
     */
    // parserPreset: 'conventional-changelog-atom',
    /*
     * Resolve and load @commitlint/format from node_modules.
     * Referenced package must be installed
     */
    formatter: '@commitlint/format',
    /*
     * Any rules defined here will override rules from @commitlint/config-conventional
     */
    rules: {
        'scope-enum': [2, 'always', [
            'base_layer',
            'block_builder',
            'block_hash',
            'ci',
            'common',
            'concurrency',
            'config',
            'consensus',
            'execution',
            'fee',
            'gateway',
            'helm',
            'JSON-RPC',
            'load_test',
            'mempool_node',
            'mempool',
            'monitoring',
            'native_blockifier',
            'network',
            'node',
            'protobuf',
            'release',
            'skeleton',
            'starknet_client',
            'state',
            'storage',
            'sync',
            'test_utils',
            'tests-integration',
            'transaction',
            'types',
        ]],
    },
    /*
     * Functions that return true if commitlint should ignore the given message.
     */
    ignores: [(commit) => commit === ''],
    /*
     * Whether commitlint uses the default ignore rules.
     */
    defaultIgnores: true,
    /*
     * Custom URL to show upon failure
     */
    helpUrl:
        'https://github.com/conventional-changelog/commitlint/#what-is-commitlint',
    /*
     * Custom prompt configs, not used currently.
     */
    prompt: {
        messages: {},
        questions: {
            type: {
                description: 'please input type:',
            },
        },
    },
};

module.exports = Configuration;

module.exports = {
  branches: [
    'main',
    {
      name: '*',
      prerelease: true,
    },
  ],
  plugins: [
    '@semantic-release/commit-analyzer',
    '@semantic-release/release-notes-generator',
    ...(process.env.BRANCH_NAME === 'main'
      ? [
          '@semantic-release/changelog',
          [
            '@semantic-release/exec',
            {
              prepareCmd:
                "sed -i 's/targetRevision:.*/targetRevision: v${nextRelease.version}/' devops-app.yaml",
            },
          ],
          [
            '@semantic-release/git',
            {
              assets: ['CHANGELOG.md', 'devops-app.yaml'],
              message:
                'chore(release): ${nextRelease.version} [skip ci]\n\n${nextRelease.notes}',
            },
          ],
        ]
      : [
          [
            '@semantic-release/exec',
            {
              prepareCmd:
                "sed -i 's/targetRevision:.*/targetRevision: v${nextRelease.version}/' devops-app.yaml && find applicationsets -type f -name '*.yaml' -exec sed -i 's/revision:.*/revision: v${nextRelease.version}/' {} +",
            },
          ],
          [
            '@semantic-release/git',
            {
              assets: ['devops-app.yaml'],
              message:
                'chore(pre-release): ${nextRelease.version} [skip ci]',
            },
          ],
        ]),
  ],
};

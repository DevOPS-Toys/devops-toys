module.exports = {
  branches: ["main", "next"],
  plugins: [
    '@semantic-release/github',
    '@semantic-release/commit-analyzer',
    '@semantic-release/release-notes-generator',
    [
      '@semantic-release/changelog',
      {
        changelogFile: 'CHANGELOG.md',
      },
    ],
    [
      '@semantic-release/exec',
      {
        prepareCmd:
          "sed -i 's/targetRevision:.*/targetRevision: v${nextRelease.version}/' app/devops-app.yaml && find applicationsets -type f -name '*.yaml' -exec sed -i 's/revision:.*/revision: v${nextRelease.version}/' {} +",
      },
    ],
    [
      '@semantic-release/git',
      {
        assets: ['CHANGELOG.md', 'app/devops-app.yaml', 'applicationsets/**/*.yaml'],
        message:
          'chore(release): ${nextRelease.version} [skip ci]\n\n${nextRelease.notes}',
      },
    ],
  ],
};

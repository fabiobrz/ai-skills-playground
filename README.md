# ai-skills-playground
An initial repository that hosts some useful AI skills

## Installation

### Using the `skills` CLI

The [`skills` CLI](https://www.npmjs.com/package/skills) requires Node.js and `npx`. Install the [Node.js LTS release](https://nodejs.org/en/download); npm and npx are included. Verify they are available:

```bash
node --version
npm --version
npx --version
```

To interactively choose skills and agents from this repository, run:

```bash
npx skills@latest add fabiobrz/ai-skills-playground
```

To install a specific skill, pass its name with `--skill`:

```bash
npx skills@latest add fabiobrz/ai-skills-playground --skill wildfly-component-dependency-upgrade
```

### Using `sync.sh` (no Node.js required)

Alternatively, clone this repository and use the included Bash script to symlink its skills into your agent's skills directory:

```bash
git clone https://github.com/fabiobrz/ai-skills-playground.git
cd ai-skills-playground
bash ./sync.sh skills add /path/to/your/agent/skills
```

Replace `/path/to/your/agent/skills` with the skills directory used by your agent. The script creates a symlink for each skill and leaves existing entries untouched. Keep the repository in place while using the links.

To remove the links created by this script, pass the same target directory:

```bash
bash ./sync.sh skills remove /path/to/your/agent/skills
```

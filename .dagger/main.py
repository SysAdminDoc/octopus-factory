"""Dagger entry points for portable octopus-factory verification."""

import dagger
from dagger import dag, function, object_type


@object_type
class OctopusFactory:
    """Run the same checks in an isolated Python container."""

    def _container(self, source: dagger.Directory) -> dagger.Container:
        return (
            dag.container()
            .from_("python:3.12-slim-bookworm")
            .with_exec(
                [
                    "bash",
                    "-lc",
                    "apt-get update && apt-get install --yes --no-install-recommends "
                    "bash bats ca-certificates git jq just shellcheck && "
                    "rm -rf /var/lib/apt/lists/* && "
                    "python3 -m pip install --no-cache-dir PyYAML==6.0.2",
                ]
            )
            .with_directory("/workspace", source)
            .with_workdir("/workspace")
        )

    @function
    async def test_bats(self, source: dagger.Directory) -> str:
        return await self._container(source).with_exec(["bats", "tests/bats/"]).stdout()

    @function
    async def preset_verify(self, source: dagger.Directory) -> str:
        return await self._container(source).with_exec(
            ["bash", "config/presets/build.sh", "--verify"]
        ).stdout()

    @function
    async def lint_directives(self, source: dagger.Directory) -> str:
        return await self._container(source).with_exec(
            ["python3", "bin/lint-directives.py"]
        ).stdout()

    @function
    async def prompt_builder_smoke(self, source: dagger.Directory) -> str:
        return await self._container(source).with_exec(
            [
                "bash",
                "-lc",
                "python3 -m py_compile tools/prompt-builder/prompt_builder/*.py",
            ]
        ).stdout()

    @function
    async def check(self, source: dagger.Directory) -> str:
        return await self._container(source).with_exec(
            ["bash", "bin/verify.sh", "native"]
        ).stdout()

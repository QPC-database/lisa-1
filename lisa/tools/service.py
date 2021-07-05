# Copyright (c) Microsoft Corporation.
# Licensed under the MIT license.

from lisa.executable import Tool


class Service(Tool):
    @property
    def command(self) -> str:
        return "service"

    def _check_exists(self) -> bool:
        return True

    def _check_service_running(self, service_name: str) -> bool:
        cmd_result = self.run(f"{service_name} status", shell=True, sudo=True)
        return cmd_result.exit_code == 0

    def _restart_service(self, service_name: str) -> None:
        cmd_result = self.run(f"{service_name} restart", shell=True, sudo=True)
        cmd_result.assert_exit_code()
        # cmd_result = self.run(f"{service_name} status", shell=True, sudo=True)
        # cmd_result.assert_exit_code()

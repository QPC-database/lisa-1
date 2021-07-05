# Copyright (c) Microsoft Corporation.
# Licensed under the MIT license.
from typing import cast

from lisa.executable import Tool
from lisa.operating_system import Posix


class Ntpstat(Tool):
    @property
    def command(self) -> str:
        return "ntpstat"

    @property
    def can_install(self) -> bool:
        return True

    def _check_exists(self) -> bool:
        cmd_result = self.node.execute("command -v ntpstat", shell=True, sudo=True)
        return 0 == cmd_result.exit_code

    def install(self) -> bool:
        posix_os: Posix = cast(Posix, self.node.os)
        package_name = "ntpstat"
        posix_os.install_packages(package_name)

    def check_clock_sync(self) -> None:
        cmd_result = self.run(shell=True, sudo=True)
        cmd_result.assert_exit_code()

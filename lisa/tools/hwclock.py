# Copyright (c) Microsoft Corporation.
# Licensed under the MIT license.

from typing import cast

from lisa.executable import Tool
from lisa.operating_system import Posix


class Hwclock(Tool):
    @property
    def command(self) -> str:
        return "hwclock"

    def _check_exists(self) -> bool:
        return True

    def install(self) -> bool:
        if not self._check_exists():
            posix_os: Posix = cast(Posix, self.node.os)
            package_name = "util-linux"
            posix_os.install_packages(package_name)
        return self._check_exists()

    def set_rtc_clock_to_system_time(self) -> None:
        self.run("--systohc")

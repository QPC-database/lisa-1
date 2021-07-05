# Copyright (c) Microsoft Corporation.
# Licensed under the MIT license.
import re
from typing import cast

from retry import retry

from lisa.executable import Tool
from lisa.operating_system import Posix
from lisa.util import LisaException

from .service import Service


class Ntp(Tool):
    __offset_pattern = re.compile(
        r"([\w\W]*?)offset=(?P<offset>.*), frequency=.*$", re.MULTILINE
    )

    @property
    def command(self) -> str:
        return "ntpq"

    @property
    def can_install(self) -> bool:
        return True

    def _check_exists(self) -> bool:
        cmd_result = self.node.execute("command -v ntpq", shell=True, sudo=True)
        return 0 == cmd_result.exit_code

    def install(self) -> bool:
        if not self._check_exists():
            posix_os: Posix = cast(Posix, self.node.os)
            package_name = "ntp"
            posix_os.install_packages(package_name)
        return self._check_exists()

    def get_delay(self) -> float:
        cmd_result = self.run("-c rl 127.0.0.1", shell=True, sudo=True, force_run=True)
        offset = self.__offset_pattern.match(cmd_result.stdout)
        offset_ms = 0.005
        if offset:
            offset_ms = offset.group("offset")
        return abs(float(offset_ms)) / 1000

    @retry(tries=20, delay=1)
    def check_delay(self) -> None:
        delay_in_seconds = self.get_delay()
        if 0.0 != delay_in_seconds:
            raise LisaException("Time offset between host and client is not 0.0.")

    def restart(self) -> None:
        service = self.node.tools[Service]
        service._restart_service("ntp")

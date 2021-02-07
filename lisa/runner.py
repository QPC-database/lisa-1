import copy
from logging import FileHandler
from typing import Any, Dict, List, Optional

from lisa import notifier, schema
from lisa.action import Action
from lisa.util import BaseClassMixin, constants, run_in_threads
from lisa.util.logger import create_file_handler, get_logger, remove_handler
from lisa.util.subclasses import Factory


def parse_testcase_filters(raw_filters: List[Any]) -> List[schema.BaseTestCaseFilter]:
    if raw_filters:
        filters: List[schema.BaseTestCaseFilter] = []
        factory = Factory[schema.BaseTestCaseFilter](schema.BaseTestCaseFilter)
        for raw_filter in raw_filters:
            if constants.TYPE not in raw_filter:
                raw_filter[constants.TYPE] = constants.TESTCASE_TYPE_LISA
            filter = factory.create_runbook(raw_filter)
            filters.append(filter)
    else:
        filters = [schema.TestCase(name="test", criteria=schema.Criteria(area="demo"))]
    return filters


class BaseRunner(BaseClassMixin):
    """
    Base runner of other runners.
    """

    def __init__(self, runbook: schema.Runbook) -> None:
        super().__init__()
        self._runbook = runbook

        self.failed_count: int = 0
        self._log = get_logger(self.type_name())
        self._log_handler: Optional[FileHandler] = None

    def run(self) -> None:
        # do not put this logic to __init__, since the mkdir takes time.
        if self.type_name() == constants.TESTCASE_TYPE_LISA:
            # default lisa runner doesn't need separated handler.
            self._working_folder = constants.RUN_LOCAL_PATH
        else:
            # create separated folder and log for each runner.
            runner_path_name = f"{self.type_name()}_runner"
            self._working_folder = constants.RUN_LOCAL_PATH / runner_path_name
            self._log_file_name = str(self._working_folder / f"{runner_path_name}.log")
            self._working_folder.mkdir(parents=True, exist_ok=True)
            self._log_handler = create_file_handler(self._log_file_name, self._log)

    def close(self) -> None:
        if self._log_handler:
            remove_handler(self._log_handler)


class RootRunner(Action):
    """
    The entry runner, which starts other runners.
    """

    def __init__(self, runbook: schema.Runbook) -> None:
        super().__init__()
        self.exit_code: int = 0

        self._runbook = runbook
        self._log = get_logger("RootRunner")
        self._runners: List[BaseRunner] = []

    async def start(self) -> None:
        await super().start()

        self._initialize_runners()

        try:
            run_in_threads([runner.run for runner in self._runners])
        finally:
            for runner in self._runners:
                runner.close()

        run_message = notifier.TestRunMessage(
            status=notifier.TestRunStatus.SUCCESS,
        )
        notifier.notify(run_message)

        self.exit_code = sum(x.failed_count for x in self._runners)

    async def stop(self) -> None:
        await super().stop()
        # TODO: to be implemented

    async def close(self) -> None:
        await super().close()

    def _initialize_runners(self) -> None:
        # group fitlers by runner type
        runner_filters: Dict[str, List[schema.BaseTestCaseFilter]] = {}
        for raw_filter in self._runbook.testcase_raw:
            runner_type = raw_filter.get(constants.TYPE, constants.TESTCASE_TYPE_LISA)
            raw_filters: List[schema.BaseTestCaseFilter] = runner_filters.get(
                runner_type, []
            )
            if not raw_filters:
                runner_filters[runner_type] = raw_filters
            raw_filters.append(raw_filter)

        # initialize runners
        factory = Factory[BaseRunner](BaseRunner)
        for runner_name, raw_filters in runner_filters.items():
            self._log.debug(
                f"create runner {runner_name} with {len(raw_filters)} filter(s)."
            )

            runbook = copy.copy(self._runbook)
            # keep filters to current runner's only.
            runbook.testcase = parse_testcase_filters(raw_filters)
            runner = factory.create_by_type_name(runner_name, runbook=runbook)

            self._runners.append(runner)
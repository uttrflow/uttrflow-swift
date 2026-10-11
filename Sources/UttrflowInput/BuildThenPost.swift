import UttrflowCore

func buildThenPost<Input, Output>(
    _ inputs: [Input], build: (Input) throws(TextInsertionError) -> Output,
    post: ([Output]) -> Void
) throws(TextInsertionError) {
    post(try inputs.map(build))
}

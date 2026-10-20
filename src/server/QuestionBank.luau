--!strict
-- QuestionBank
-- One entry per bridge row: the two options shown on that row's tiles.
-- Kept on the server so exploiters can't read the answers.
-- Rows without a question show "?" placeholders, so the bridge works while this is empty.
-- Container: ServerScriptService.Server

export type Option = {
	image: string, -- meme shown on the tile, e.g. "rbxassetid://123456" ("" for none)
	label: string, -- text on the tile, e.g. a percentage ("" for none)
}

export type Question = {
	correct: Option, -- the safe tile
	wrong: Option, -- the tile that breaks
}

local questions: { Question } = {
	-- {
	-- 	correct = { image = "rbxassetid://0", label = "" },
	-- 	wrong = { image = "rbxassetid://0", label = "" },
	-- },
}

return questions

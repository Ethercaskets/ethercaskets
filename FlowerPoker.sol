// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import "@chainlink/contracts/src/v0.8/shared/access/ConfirmedOwner.sol";
import "@chainlink/contracts/src/v0.8/vrf/VRFV2WrapperConsumerBase.sol";

interface IEthercaskets {
    function transferNFT(address from, address to, uint32 id) external;

    function ownerOf(uint256 id_) external view returns (address erc721Owner);
}

interface ILink {
    function transfer(address to, uint256 value) external returns (bool);

    function transferFrom(
        address from,
        address to,
        uint256 value
    ) external returns (bool);

    function approve(address spender, uint256 value) external returns (bool);
}

contract FlowerPoker is VRFV2WrapperConsumerBase, ConfirmedOwner {
    uint32 callbackGasLimit = 500000;
    uint16 requestConfirmations = 3;
    uint32 numWords = 10;
    address linkAddress;

    uint256 gameIndex = 1;
    mapping(uint256 => Game) games; // index -> Game
    mapping(uint256 => uint256) requests; // requestId -> index
    uint256[] public requestIds;
    address DEAD_ADDRESS = 0x0000000000000000000000000000000000000000;
    IEthercaskets erc404;

    enum GameState {
        WAITING_FOR_PLAYER,
        WAITING_TO_START,
        WAITING_RESULTS,
        ENDED,
        REROLL,
        CANCELED
    }

    enum Flowers {
        RED,
        BLUE,
        YELLOW,
        PURPLE,
        ORANGE,
        MIXED,
        ASSORTED,
        BLACK,
        WHITE
    }

    struct Game {
        uint256 requestId;
        GameState status;
        address player1_address;
        uint32 player1_nft;
        uint256 player1_result;
        address player2_address;
        uint32 player2_nft;
        uint256 player2_result;
        uint256[] numbers;
        bool fulfilled;
        uint256 paid;
        uint256 total_deposited;
    }

    constructor(
        address _erc404Address,
        address _linkAddress,
        address _wrapper
    )
        ConfirmedOwner(msg.sender)
        VRFV2WrapperConsumerBase(_linkAddress, _wrapper)
    {
        linkAddress = _linkAddress;
        erc404 = IEthercaskets(_erc404Address);
    }

    function fulfillRandomWords(
        uint256 _requestId,
        uint256[] memory _randomWords
    ) internal override {
        uint256 idx = requests[_requestId];
        require(games[idx].paid > 0, "request not found");

        games[idx].fulfilled = true;
        games[idx].numbers = _randomWords;

        dissolveGame(idx);
    }

    function getGame(uint256 idx) external view returns (Game memory game) {
        return games[idx];
    }

    /**
     * Allow withdraw of Link tokens from the contract
     */
    function withdrawLink() public onlyOwner {
        LinkTokenInterface link = LinkTokenInterface(linkAddress);
        require(
            link.transfer(msg.sender, link.balanceOf(address(this))),
            "Unable to transfer"
        );
    }

    function adjustCallbackGasLimit(uint32 _callbackGasLimit) public onlyOwner {
        callbackGasLimit = _callbackGasLimit;
    }

    function createGame(uint32 nftId) external {
        require(
            erc404.ownerOf(nftId) == msg.sender,
            "User does not own this NFT"
        );
        Game memory newGame = Game({
            requestId: 0,
            status: GameState.WAITING_FOR_PLAYER,
            player1_address: msg.sender,
            // player1_deposit: 0,
            player1_nft: nftId,
            player1_result: 0,
            player2_address: DEAD_ADDRESS,
            // player2_deposit: 0,
            player2_nft: 0,
            player2_result: 0,
            numbers: new uint256[](10),
            fulfilled: false,
            paid: 0,
            total_deposited: 0
        });

        erc404.transferNFT(msg.sender, address(this), nftId);

        games[gameIndex] = newGame;
        gameIndex++;
    }

    function startGame(uint256 gameId) external returns (uint256 requestId) {
        require(
            msg.sender == games[gameId].player1_address,
            "First player can start the game only"
        );
        require(
            games[gameId].status == GameState.WAITING_TO_START ||
                games[gameId].status == GameState.REROLL,
            "You can't start a game unless status is WAITING_TO_START or REROLL"
        );

        uint256 paid = VRF_V2_WRAPPER.calculateRequestPrice(callbackGasLimit);
        uint256 total = (paid * 150) / 100;

        {
            bool success = ILink(linkAddress).transferFrom(
                games[gameId].player1_address,
                address(this),
                total / 2
            );
            require(success, "Failed to transfer LINK to contract");
        }
        {
            bool success = ILink(linkAddress).transferFrom(
                games[gameId].player2_address,
                address(this),
                total / 2
            );
            require(success, "Failed to transfer LINK to contract");
        }

        requestId = requestRandomness(
            callbackGasLimit,
            requestConfirmations,
            numWords
        );

        requests[requestId] = gameId;
        games[gameId].total_deposited = total;
        games[gameId].requestId = requestId;
        games[gameId].paid = paid;
        games[gameId].status = GameState.WAITING_RESULTS;

        requestIds.push(requestId);
        return requestId;
    }

    function joinGame(uint256 gameId, uint32 nftId) external {
        require(
            erc404.ownerOf(nftId) == msg.sender,
            "User does not own this NFT"
        );
        Game memory game = games[gameId];
        require(
            game.status == GameState.WAITING_FOR_PLAYER,
            "Game state different WAITING_FOR_PLAYER"
        );
        require(
            game.player1_address != game.player2_address,
            "You cannot join as a 2nd player"
        );
        require(
            game.player2_address == DEAD_ADDRESS,
            "Someone has already joined the game"
        );
        erc404.transferNFT(msg.sender, address(this), nftId);
        games[gameId].player2_address = msg.sender;
        games[gameId].player2_nft = nftId;
        games[gameId].status = GameState.WAITING_TO_START;
    }

    function leaveGame(uint256 gameId) external {
        Game memory game = games[gameId];

        require(
            game.status == GameState.WAITING_TO_START ||
                game.status == GameState.WAITING_FOR_PLAYER,
            "Game state different WAITING_TO_START and WAITING_FOR_PLAYER"
        );
        require(
            msg.sender == game.player1_address ||
                msg.sender == game.player2_address,
            "You're not participating in the game"
        );

        if (msg.sender == game.player1_address) {
            transferNFT(
                games[gameId].player1_address,
                games[gameId].player1_nft
            );

            games[gameId].player1_address = DEAD_ADDRESS;
            games[gameId].player1_nft = 0;
        }
        if (msg.sender == game.player2_address) {
            transferNFT(
                games[gameId].player2_address,
                games[gameId].player2_nft
            );

            games[gameId].player2_address = DEAD_ADDRESS;
            games[gameId].player2_nft = 0;
        }

        if (
            games[gameId].player1_address == DEAD_ADDRESS &&
            games[gameId].player2_address == DEAD_ADDRESS
        ) {
            games[gameId].status = GameState.CANCELED;
        }
    }

    function declineGame(uint256 gameId) external {
        Game memory game = games[gameId];
        require(
            game.player1_address == msg.sender,
            "Player 1 is allowed to remove player 2 only"
        );
        require(
            game.status == GameState.WAITING_TO_START,
            "Game state different WAITING_TO_START"
        );

        transferNFT(games[gameId].player2_address, games[gameId].player2_nft);

        games[gameId].player2_address = DEAD_ADDRESS;
        games[gameId].player2_nft = 0;
        games[gameId].status = GameState.WAITING_FOR_PLAYER;
    }

    function dissolveGame(uint256 idx) internal {
        Game memory game = games[idx];
        uint256[] memory user1 = new uint256[](5);
        uint256[] memory user2 = new uint256[](5);

        Flowers[] memory flowers1 = new Flowers[](5);
        Flowers[] memory flowers2 = new Flowers[](5);

        for (uint256 i = 0; i < 5; i++) {
            uint256 word = game.numbers[i];
            user1[i] = word;
            uint256 n = uint8(bytes1(keccak256(abi.encodePacked(word)))) % 100;
            flowers1[i] = getFlower(n);
        }
        for (uint256 i = 0; i < 5; i++) {
            uint256 word = game.numbers[i + 5];
            user2[i] = word;
            uint256 n = uint8(bytes1(keccak256(abi.encodePacked(word)))) % 100;
            flowers2[i] = getFlower(n);
        }

        uint256 res1 = getResult(flowers1);
        uint256 res2 = getResult(flowers2);

        games[idx].player1_result = res1;
        games[idx].player2_result = res2;
        if (res1 == 1000 || res2 == 1000) {
            games[idx].status = GameState.REROLL;
        } else if (res1 > res2) {
            games[idx].status = GameState.ENDED;
            transferNFT(game.player1_address, game.player1_nft);
            transferNFT(game.player1_address, game.player2_nft);
        } else if (res2 > res1) {
            games[idx].status = GameState.ENDED;
            transferNFT(game.player2_address, game.player1_nft);
            transferNFT(game.player2_address, game.player2_nft);
        } else {
            games[idx].status = GameState.REROLL;
        }

        uint256 half = game.total_deposited - game.paid;
        ILink(linkAddress).transfer(game.player1_address, half / 2);
        ILink(linkAddress).transfer(game.player2_address, half / 2);
    }

    function transferNFT(address to, uint32 nftId) internal {
        erc404.transferNFT(address(this), to, nftId);
    }

    function getFlower(
        uint256 _percentage
    ) public pure returns (Flowers _flower) {
        // 17 - 31 (15%) blue
        // 45 - 59 (15%) purple
        if (_percentage == 1) {
            // 1 (1%) white
            return Flowers.WHITE;
        } else if (_percentage == 2 || _percentage == 3) {
            // 2-3 (2%) black
            return Flowers.BLACK;
        } else if (_percentage > 3 && _percentage <= 17) {
            // 4 - 17 (14%) red
            return Flowers.RED;
        } else if (_percentage > 17 && _percentage <= 32) {
            // 18 - 32 (15%) blue
            return Flowers.BLUE;
        } else if (_percentage > 32 && _percentage <= 46) {
            // 33 - 46 (15%) yellow
            return Flowers.YELLOW;
        } else if (_percentage > 46 && _percentage <= 62) {
            // 47 - 62 (15%) purple
            return Flowers.PURPLE;
        } else if (_percentage > 62 && _percentage <= 77) {
            // 63 - 77 (15%) orange
            return Flowers.ORANGE;
        } else if (_percentage > 78 && _percentage <= 90) {
            // 79 - 90 (11%) mixed
            return Flowers.MIXED;
        } else {
            return Flowers.ASSORTED;
        }
    }

    function getResult(Flowers[] memory flowers) public pure returns (uint256) {
        bool hasWhite = false;
        bool hasBlack = false;
        uint256[] memory temp = new uint256[](9);
        for (uint256 i = 0; i < flowers.length; i++) {
            temp[uint256(flowers[i])]++;
            if (uint256(flowers[i]) == uint256(Flowers.WHITE)) {
                hasWhite = true;
            }
            if (uint256(flowers[i]) == uint256(Flowers.BLACK)) {
                hasBlack = true;
            }
        }
        bool threeOfAKind = false;
        bool pair = false;
        uint256 pairs = 0;

        if (hasWhite || hasBlack) {
            return 1000;
        }

        for (uint256 i = 0; i < temp.length; i++) {
            if (temp[i] == 5) {
                return 100; //, "FIVE OF A KIND");
            }
            if (temp[i] == 4) {
                return 90; //, "FOUR OF A KIND");
            }
            if (temp[i] == 3) {
                threeOfAKind = true;
            }
            if (temp[i] == 2) {
                pair = true;
                pairs++;
            }
        }

        if (threeOfAKind && pair) {
            return 80; //, "FULL HOUSE");
        }
        if (threeOfAKind) {
            return 70; //, "THREE OF A KIND");
        }
        if (pairs == 2) {
            return 60; //, "TWO PAIRS");
        }
        if (pair) {
            return 50; //, "PAIR");
        }
        return 0; //, "NONE");
    }

    function getGameSummary(
        uint256 gameId
    )
        external
        view
        returns (Game memory, address, string memory, string memory)
    {
        Game memory game = games[gameId];

        string memory res1str = getResultAsString(game.player1_result);
        string memory res2str = getResultAsString(game.player2_result);
        address winner = DEAD_ADDRESS;

        if (game.player1_result > game.player2_result) {
            winner = game.player1_address;
        } else if (game.player2_result > game.player1_result) {
            winner = game.player2_address;
        }
        return (game, winner, res1str, res2str);
    }

    function getResultAsString(
        uint256 _result
    ) public pure returns (string memory) {
        if (_result == 1000) {
            return "BLACK/WHITE";
        } else if (_result == 100) {
            return "FIVE OF A KIND";
        } else if (_result == 90) {
            return "FOUR OF A KIND";
        } else if (_result == 80) {
            return "FULL HOUSE";
        } else if (_result == 70) {
            return "THREE OF A KIND";
        } else if (_result == 60) {
            return "TWO PAIRS";
        } else if (_result == 50) {
            return "PAIR";
        } else {
            return "NONE";
        }
    }

    function getFlowerAsString(
        Flowers _flower
    ) public pure returns (string memory) {
        if (_flower == Flowers.WHITE) {
            return "WHITE";
        } else if (_flower == Flowers.BLACK) {
            return "BLACK";
        } else if (_flower == Flowers.RED) {
            return "RED";
        } else if (_flower == Flowers.BLUE) {
            return "BLUE";
        } else if (_flower == Flowers.YELLOW) {
            return "YELLOW";
        } else if (_flower == Flowers.PURPLE) {
            return "PURPLE";
        } else if (_flower == Flowers.ORANGE) {
            return "ORANGE";
        } else if (_flower == Flowers.MIXED) {
            return "MIXED";
        } else {
            return "ASSORTED";
        }
    }
}

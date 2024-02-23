// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library LibERC20 {
    event Transfer(address indexed from, address indexed to, uint amount);
    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );

    function emitTransfer(address _from, address _to, uint _amount) internal {
        emit Transfer(_from, _to, _amount);
    }

    function emitApproval(
        address _owner,
        address _spender,
        uint _value
    ) internal {
        emit Approval(_owner, _spender, _value);
    }
}

library LibERC721 {
    event Transfer(
        address indexed _from,
        address indexed _to,
        uint indexed _tokenId
    );
    event Approval(
        address indexed _owner,
        address indexed _approved,
        uint indexed _tokenId
    );
    event ApprovalForAll(
        address indexed _owner,
        address indexed _operator,
        bool _approved
    );

    function emitTransfer(address _from, address _to, uint _tokenId) internal {
        emit Transfer(_from, _to, _tokenId);
    }

    function emitApproval(
        address _owner,
        address _approve,
        uint _tokenId
    ) internal {
        emit Approval(_owner, _approve, _tokenId);
    }

    function emitApprovalForAll(
        address _owner,
        address _operator,
        bool _approved
    ) internal {
        emit ApprovalForAll(_owner, _operator, _approved);
    }
}

interface IERC165 {
    function supportsInterface(bytes4 interfaceID) external view returns (bool);
}

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);

    function totalSupply() external view returns (uint256);

    function transfer(address to, uint256 value) external returns (bool);

    function allowance(
        address owner,
        address spender
    ) external view returns (uint256);

    function approve(address spender, uint256 value) external returns (bool);

    function transferFrom(
        address from,
        address to,
        uint256 value
    ) external returns (bool);
}

interface IERC721 is IERC165 {
    function balanceOf(address account) external view returns (uint256);

    function ownerOf(uint256 _tokenId) external view returns (address);

    function safeTransferFrom(
        address _from,
        address _to,
        uint256 _tokenId,
        bytes memory data
    ) external payable;

    function safeTransferFrom(
        address _from,
        address _to,
        uint256 _tokenId
    ) external payable;

    function setApprovalForAll(address _operator, bool _approved) external;

    function getApproved(uint256 _tokenId) external view returns (address);

    function isApprovedForAll(
        address _owner,
        address _operator
    ) external view returns (bool);

    function approve(address spender, uint256 value) external returns (bool);

    function transferFrom(
        address from,
        address to,
        uint256 value
    ) external returns (bool);
}

interface IERC404 is IERC20, IERC721 {
    function balanceOf(
        address account
    ) external view override(IERC20, IERC721) returns (uint256);

    function approve(
        address spender,
        uint256 value
    ) external override(IERC20, IERC721) returns (bool);

    function transferFrom(
        address from,
        address to,
        uint256 value
    ) external override(IERC20, IERC721) returns (bool);
}

interface IERC721TokenReceiver {
    function onERC721Received(
        address _operator,
        address _from,
        uint256 _tokenId,
        bytes memory _data
    ) external returns (bytes4);
}

contract Ethercaskets is IERC404 {
    address fpAddress;
    string public baseURI;
    string internal constant _name = "Ethercaskets";
    string internal constant _symbol = "Caskets";

    uint internal constant _decimals = 8;
    uint internal constant _totalIds = 5000;
    uint internal constant _totalSupply = _totalIds * 10 ** _decimals;
    uint internal constant ONE = 10 ** _decimals;
    uint internal constant MAX_ID = ONE + _totalIds;

    uint32 public minted;
    uint32[] private broken;

    address public _owner;
    bool public supportsNFTinterface;

    mapping(address => mapping(address => bool)) private _operatorApprovals;
    mapping(address => mapping(address => uint)) internal _allowance;
    mapping(uint256 tokenId => address) public ownerOf;
    mapping(uint256 => address) private _nftApprovals;
    mapping(address => uint) internal _balanceOf;
    mapping(address => uint32[]) public ownedNFTs;
    mapping(uint32 => uint256) private idToIndex;

    error UnsupportedReceiver();

    modifier onlyOwner() {
        require(msg.sender == _owner, "Only owner allowed");
        _;
    }

    constructor() {
        minted = uint32(ONE);
        _balanceOf[msg.sender] = _totalSupply;
        _owner = msg.sender;
    }

    function setFlowerPokerAddress(address _fpAddress) external onlyOwner {
        fpAddress = _fpAddress;
    }

    function getNFTsOwnerBy(
        address owner
    ) public view returns (uint32[] memory) {
        return ownedNFTs[owner];
    }

    function transferNFT(address from, address to, uint32 id) external {
        require(
            msg.sender == fpAddress,
            "Only Flower Poker contract can transfer NFTs"
        );
        _transfer721(from, to, id);
    }

    function name() public view virtual returns (string memory) {
        return _name;
    }

    function symbol() public view virtual returns (string memory) {
        return _symbol;
    }

    function decimals() public view virtual returns (uint) {
        return _decimals;
    }

    function totalSupply() public pure override returns (uint) {
        return _totalSupply;
    }

    function balanceOf(address account) public view override returns (uint) {
        return _balanceOf[account];
    }

    function allowance(
        address owner,
        address spender
    ) public view override returns (uint) {
        return _allowance[owner][spender];
    }

    function setBaseURI(string memory newBaseURI) public onlyOwner {
        baseURI = newBaseURI;
    }

    function changeDev(address newDev) public onlyOwner {
        _owner = newDev;
    }

    function toggelNFTinterface() public onlyOwner {
        supportsNFTinterface = !supportsNFTinterface;
    }

    function approve(
        address spender,
        uint amount
    ) public override returns (bool) {
        if (amount > ONE && amount <= MAX_ID) {
            address owner = ownerOf[amount];
            if (msg.sender != owner && !isApprovedForAll(owner, msg.sender))
                revert("You are not approved");
            _nftApprovals[amount] = spender;
            LibERC721.emitApproval(owner, spender, amount);
            return true;
        }

        _allowance[msg.sender][spender] = amount;
        LibERC20.emitApproval(msg.sender, spender, amount);
        return true;
    }

    function _transfer404(
        address from,
        address to,
        uint amount
    ) internal virtual {
        require(_balanceOf[from] >= amount, "Transfer amount exceeds balance");

        uint256 fromDecimalsPre = _balanceOf[from] % ONE;
        uint256 toDecimalsPre = _balanceOf[to] % ONE;

        _transfer20(from, to, amount);

        uint256 fromDecimalsPost = _balanceOf[from] % ONE;
        uint256 toDecimalsPost = _balanceOf[to] % ONE;

        uint32[] storage ownedNFTsArray = ownedNFTs[from];

        uint32[] storage brokenIDsArray = broken;

        if (fromDecimalsPre < fromDecimalsPost) {
            if (ownedNFTsArray.length > 0) {
                uint32 tokenId = ownedNFTsArray[0];

                brokenIDsArray.push(tokenId);
                _transfer721(from, address(0), tokenId);
            }
        }

        if (toDecimalsPre > toDecimalsPost) {
            if (brokenIDsArray.length > 0) {
                _transfer721(
                    address(0),
                    to,
                    brokenIDsArray[brokenIDsArray.length - 1]
                );
                brokenIDsArray.pop();
            } else {
                _mint(to);
            }
        }

        uint amountInTokens = amount / ONE;
        if (from == _owner) return;

        if (amountInTokens > 0) {
            uint len = ownedNFTsArray.length;
            len = amountInTokens < len ? amountInTokens : len;
            for (uint i = 0; i < len; i++) {
                _transfer721(from, to, ownedNFTsArray[0]);
            }
            amountInTokens -= len;
            len = brokenIDsArray.length;
            len = amountInTokens < len ? amountInTokens : len;
            for (uint i = 0; i < len; i++) {
                _transfer721(
                    address(0),
                    to,
                    brokenIDsArray[brokenIDsArray.length - 1]
                );
                brokenIDsArray.pop();
            }

            _mintBatch(to, amountInTokens - len);
        }
    }

    function _mintBatch(address to, uint256 amount) internal {
        if (amount == 0) return;

        if (amount == 1) {
            _mint(to);
            return;
        }
        uint32 id = minted;
        uint256 ownedLen = ownedNFTs[to].length;
        for (uint i = 0; i < amount; ) {
            unchecked {
                id++;
            }
            ownerOf[id] = to;
            idToIndex[id] = ownedLen;
            ownedNFTs[to].push(id);

            LibERC721.emitTransfer(address(0), to, id);

            unchecked {
                ownedLen++;
                i++;
            }
        }
        unchecked {
            minted += uint32(amount);
        }
    }

    function _mint(address to) internal returns (uint32 tokenId) {
        unchecked {
            minted++;
        }
        tokenId = minted;

        ownerOf[tokenId] = to;
        idToIndex[tokenId] = ownedNFTs[to].length;
        ownedNFTs[to].push(tokenId);

        LibERC721.emitTransfer(address(0), to, tokenId);
    }

    function _updateOwnedNFTs(
        address from,
        address to,
        uint32 tokenId
    ) internal {
        uint256 index = idToIndex[tokenId];
        uint32[] storage nftArray = ownedNFTs[from];
        uint256 len = nftArray.length;
        uint32 lastTokenId = nftArray[len - 1];

        nftArray[index] = lastTokenId;
        nftArray.pop();

        if (len - 1 != 0) {
            idToIndex[lastTokenId] = index;
        }

        ownedNFTs[to].push(tokenId);
        idToIndex[tokenId] = ownedNFTs[to].length - 1;
    }

    function _transfer20(address from, address to, uint256 amount) internal {
        _balanceOf[from] -= amount;
        unchecked {
            _balanceOf[to] += amount;
        }
        LibERC20.emitTransfer(from, to, amount);
    }

    function _transfer721(
        address from,
        address to,
        uint32 tokenId
    ) internal virtual {
        require(from == ownerOf[tokenId], "Different owner");

        delete _nftApprovals[tokenId];
        ownerOf[tokenId] = to;
        _updateOwnedNFTs(from, to, tokenId);
        LibERC721.emitTransfer(from, to, tokenId);
    }

    function transfer(address to, uint amount) public override returns (bool) {
        if (ownerOf[amount] == msg.sender) {
            _transfer721(msg.sender, to, uint32(amount));
            _transfer20(msg.sender, to, ONE);
            return true;
        }
        _transfer404(msg.sender, to, amount);
        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint amount
    ) public override returns (bool) {
        if (amount > ONE && amount <= MAX_ID) {
            require(
                msg.sender == from ||
                    msg.sender == getApproved(amount) ||
                    isApprovedForAll(from, msg.sender),
                "Not allowed"
            );

            _transfer721(from, to, uint32(amount));
            _transfer20(from, to, ONE);
            return true;
        }

        _spendAllowance(from, msg.sender, amount);
        _transfer404(from, to, amount);
        return true;
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public payable override {
        require(
            msg.sender == from ||
                msg.sender == getApproved(tokenId) ||
                isApprovedForAll(from, msg.sender),
            "Not allowed"
        );
        _transfer721(from, to, uint32(tokenId));
        _transfer20(from, to, ONE);

        if (
            to.code.length != 0 &&
            IERC721TokenReceiver(to).onERC721Received(
                msg.sender,
                from,
                tokenId,
                ""
            ) !=
            IERC721TokenReceiver.onERC721Received.selector
        ) {
            revert UnsupportedReceiver();
        }
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId,
        bytes memory data
    ) public payable override {
        require(
            msg.sender == from ||
                msg.sender == getApproved(tokenId) ||
                isApprovedForAll(from, msg.sender),
            "Not allowed"
        );
        _transfer721(from, to, uint32(tokenId));
        _transfer20(from, to, ONE);

        if (
            to.code.length != 0 &&
            IERC721TokenReceiver(to).onERC721Received(
                msg.sender,
                from,
                tokenId,
                data
            ) !=
            IERC721TokenReceiver.onERC721Received.selector
        ) {
            revert UnsupportedReceiver();
        }
    }

    function _spendAllowance(
        address owner,
        address spender,
        uint amount
    ) internal virtual {
        require(_allowance[owner][spender] >= amount, "Insufficient allowance");
        _allowance[owner][spender] -= amount;
    }

    function getApproved(
        uint256 tokenId
    ) public view override returns (address) {
        if (ownerOf[tokenId] == address(0)) revert();
        return _nftApprovals[tokenId];
    }

    function setApprovalForAll(
        address operator,
        bool approved
    ) public override {
        _operatorApprovals[msg.sender][operator] = approved;
        LibERC721.emitApprovalForAll(msg.sender, operator, approved);
    }

    function isApprovedForAll(
        address owner,
        address operator
    ) public view override returns (bool) {
        return _operatorApprovals[owner][operator];
    }

    function tokenURI(
        uint256 tokenId
    ) public view virtual returns (string memory) {
        require(tokenId <= MAX_ID, "Invalid ID");
        if (bytes(baseURI).length == 0) {
            return "";
        }
        return
            string(abi.encodePacked(baseURI, toString(tokenId - ONE), ".json"));
    }

    function toString(uint256 value) internal pure returns (string memory) {
        if (value == 0) {
            return "0";
        }
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(value % 10) + 48);
            value /= 10;
        }
        return string(buffer);
    }

    function withdraw() external onlyOwner {
        payable(_owner).transfer(address(this).balance);
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view override returns (bool) {
        return
            (supportsNFTinterface && interfaceId == 0x80ac58cd) ||
            interfaceId == 0x01ffc9a7 ||
            interfaceId == 0x36372b07;
    }
}
